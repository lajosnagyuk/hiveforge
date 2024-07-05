#!/bin/bash

HELM_VERSION="3.15.2"
POSTGRES_OPERATOR_VERSION="1.12.2"

# Is this darwin? Is this Linux?
check_platform() {
    if [ "$(uname)" == "Darwin" ]; then
        # Do something under Mac OS X platform
        platform="mac"
    elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
        # Do something under GNU/Linux platform
        platform="linux"
    fi
}

check_arch() {
    if [ "$(uname -m)" == "x86_64" ]; then
        arch="amd64"
    elif [ "$(uname -m)" == "arm64" ]; then
        # Do something under GNU/Linux platform
        arch="arm64"
    elif [ "$(uname -m)" == "arm" ]; then
        # Do something under GNU/Linux platform
        arch="arm"
    elif [ "$(uname -m)" == "aarch64" ]; then
        # Do something under GNU/Linux platform
        arch="arm64"
    elif [ "$(uname -m)" == "riscv64" ]; then
        # Do something under GNU/Linux platform
        arch="riscv64"
    fi
}

install_brew() {
    if ! [ -x "$(command -v brew)" ]; then
        echo 'Error: brew is not installed.' >&2
        echo 'Would you like to install it? (yY/nN)'
        read answer
        if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        else
            echo 'Exiting...'
            exit 1
        fi
    fi
}

# This script can be used to install and maintain a postgres database, using the bitnami chart

# First check if we have helm, kubectl installed and that the context for kubectl is set
install_helm() {
    if ! [ -x "$(command -v helm)" ]; then
        echo 'Error: helm is not installed.' >&2
        echo 'Would you like to install it? (yY/nN)'
        read answer
        if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then
            if [ "$platform" == "mac" ]; then
                install_brew
                brew install helm
            elif [ "$platform" == "linux" ]; then
                check_arch
                curl -LO https://get.helm.sh/helm-v${HELM_VERSION}-linux-${arch}.tar.gz
                tar -zxvf helm-v${HELM_VERSION}-linux-${arch}.tar.gz
                sudo mv linux-${arch}/helm /usr/local/bin/helm
            fi
        else
            echo 'Exiting...'
            exit 1
        fi
    fi
}

install_kubectl() {
    if ! [ -x "$(command -v kubectl)" ]; then
        echo 'Error: kubectl is not installed.' >&2
        echo 'Would you like to install it? (yY/nN)'
        read answer
        if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then
            if [ "$platform" == "mac" ]; then
                install_brew
                check_arch
                curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/${arch}/kubectl"
                chmod +x ./kubectl
                sudo mv ./kubectl /usr/local/bin/kubectl
                echo "Please set up your kubectl context before proceeding."
                exit 1
            elif [ "$platform" == "linux" ]; then
                check_arch
                curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${arch}/kubectl"
                chmod +x ./kubectl
                sudo mv ./kubectl /usr/local/bin/kubectl
                echo "Please set up your kubectl context before proceeding."
                exit 1
            fi
        else
            echo 'Not installing Kubectl. Exiting...'
            exit 1
        fi
    fi
}

check_hiveforge_controller_secret(){
    kubectl get secret hiveforge-database-secret --namespace hiveforge-controller
    if [ $? -ne 0 ]; then
        echo "Replicating secret to hiveforge-controller namespace..."
        kubectl create secret generic hiveforge-database-secret \
        --namespace hiveforge-controller \
        --from-literal=postgres-password=${postgres_password} \
        --from-literal=replication-password=${postgres_replicator_password} \
        --from-literal=postgres-username=${postgres_user} \
        --from-literal=pgpool-admin-username=${pgpool_admin_username} \
        --from-literal=pgpool-admin-password=${pgpool_admin_password}

    fi
}

install_postgres_operator() {
    # check namespace
    kubectl get namespace postgres-operator
    if [ $? -ne 0 ]; then
        echo "Namespace didn't exist, creating postgres-operator namespace"
        kubectl create namespace postgres-operator
    fi

    # add zalando postgres-operator repo
    helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator

    # install postgres-operator
    helm upgrade --install postgres-operator postgres-operator-charts/postgres-operator \
        --namespace postgres-operator \
        --version ${POSTGRES_OPERATOR_VERSION} \
        --set watchedNamespace=hiveforge-database

    # Wait for the operator to be ready
    kubectl rollout status deployment postgres-operator -n postgres-operator

    # Create PostgreSQL cluster
    cat <<EOF | kubectl apply -f -
apiVersion: "acid.zalan.do/v1"
kind: postgresql
metadata:
  name: hiveforge-cluster
  namespace: hiveforge-database
spec:
  enableConnectionPooler: true
  connectionPooler:
    numberOfInstances: 3
  teamId: "hiveforge"
  volume:
    size: 10Gi
  numberOfInstances: 3
  users:
    hiveforgecontroller: []
  databases:
    hiveforge-database: hiveforgecontroller
  postgresql:
    version: "15"
EOF

    # Wait for the cluster to be ready
    kubectl wait --for=condition=Ready --timeout=300s postgresql/hiveforge-cluster -n hiveforge-database

    # Create secret for hiveforge-controller
    POSTGRES_PASSWORD=$(kubectl get secret hiveforge-cluster.hiveforgecontroller.credentials.postgresql.acid.zalan.do -n hiveforge-database -o jsonpath='{.data.password}' | base64 --decode)

    kubectl create secret generic hiveforge-database-secret \
        --namespace hiveforge-controller \
        --from-literal=postgres-password=${POSTGRES_PASSWORD} \
        --from-literal=postgres-username=hiveforgecontroller \
        --from-literal=postgres-host=hiveforge-cluster \
        --from-literal=postgres-port=5432 \
        --from-literal=postgres-database=hiveforge-database
}

main() {
    check_platform
    install_helm
    install_kubectl
    install_postgres_operator
}

main
