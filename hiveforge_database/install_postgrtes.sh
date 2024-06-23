#!/bin/bash

HELM_VERSION="3.15.2"
POSTGRES_CHART_VERSION="14.2.7"

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

install_postgres() {
    # check namespace
    kubectl get namespace hiveforge-database
    if [ $? -ne 0 ]; then
        echo "namespace didn't exist, installing"
        kubectl create namespace hiveforge-database
        kubectl label namespace hiveforge-database app=hiveforge-database
    fi
    postgres_password=$(openssl rand -base64 12)
    postgres_replicator_password=$(openssl rand -base64 12)
    postgres_user=hiveforgecontroller
    postgres_database=hiveforge-database
    postgres_replica_count=3
    pgpool_replica_count=3
    pgpool_admin_username=pgpool
    pgpool_admin_password=$(openssl rand -base64 12)
    # check secret exists
    kubectl get secret hiveforge-database-secret --namespace hiveforge-database
    if [ $? -eq 0 ]; then
        echo "Secret already exists. Setting variables for upgrade step..."
        # set variables from secret
        postgres_password=$(kubectl get secret hiveforge-database-secret --namespace hiveforge-database -o jsonpath="{.data.postgres-password}" | base64 --decode)
        postgres_replicator_password=$(kubectl get secret hiveforge-database-secret --namespace hiveforge-database -o jsonpath="{.data.replication-password}" | base64 --decode)
        postgres_user=$(kubectl get secret hiveforge-database-secret --namespace hiveforge-database -o jsonpath="{.data.postgres-username}" | base64 --decode)
        pgpool_admin_username=$(kubectl get secret hiveforge-database-secret --namespace hiveforge-database -o jsonpath="{.data.pgpool-admin-username}" | base64 --decode)
        pgpool_admin_password=$(kubectl get secret hiveforge-database-secret --namespace hiveforge-database -o jsonpath="{.data.pgpool-admin-password}" | base64 --decode)

    else
        echo "Creating secret..."
        kubectl create secret generic hiveforge-database-secret \
          --namespace hiveforge-database \
          --from-literal=postgres-password=${postgres_password} \
          --from-literal=replication-password=${postgres_replicator_password} \
          --from-literal=postgres-username=${postgres_user} \
          --from-literal=pgpool-admin-username=${pgpool_admin_username} \
          --from-literal=pgpool-admin-password=${pgpool_admin_password}
    fi
    # add bitnami repo
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm upgrade --install hiveforge-database bitnami/postgresql-ha \
    --namespace ${postgres_database} \
    --version ${POSTGRES_CHART_VERSION} \
    --set global.postgresql.postgresqlDatabase=hiveforge-database \
    --set global.postgresql.postgresqlUsername=${postgres_user} \
    --set global.postgresql.postgresqlPassword=${postgres_password} \
    --set global.postgresql.repmgrPassword=${postgres_replicator_password} \
    --set postgresql.replicaCount=${postgres_replica_count} \
    --set pgpool.replicaCount=${pgpool_replica_count} \
    --set global.pgpool.adminUsername=${pgpool_admin_username} \
    --set global.pgpool.adminPassword=${pgpool_admin_password} \
    --set pgpool.enabled=true
}

main() {
    check_platform
    install_helm
    install_kubectl
    install_postgres
}

main
