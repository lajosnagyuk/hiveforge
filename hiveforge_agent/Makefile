# Default arguments
MIX_ENV ?= prod
APP_DIR ?= /app
APP_NAME ?= hiveforge_agent
DOCKER_BUILDX_PLATFORMS ?= linux/amd64,linux/arm64
DOCKER_REGISTRY ?= quay.io
DOCKER_REPO ?= lajos_nagy/hiveforge-agent
DOCKER_TAG ?= latest
HIVEFORGE_CONTROLLER_API_ENDPOINT ?= https://host.docker.internal:4000/
HIVEFORGE_CA_CERT_PATH ?= /hiveforge_agent/misc/certificates/ca-cert.pem

# Docker Buildx setup
DOCKER_BUILDX ?= docker buildx
DOCKER_BUILDX_BUILDER ?= multi-arch-builder

.PHONY: all buildx-setup build push clean

all: build push

buildx-setup:
	# Check if the builder instance already exists
	if ! $(DOCKER_BUILDX) inspect $(DOCKER_BUILDX_BUILDER) &>/dev/null; then \
		$(DOCKER_BUILDX) create --name $(DOCKER_BUILDX_BUILDER) --use; \
	else \
		echo "Builder instance $(DOCKER_BUILDX_BUILDER) already exists"; \
	fi
	# Boot the builder instance
	$(DOCKER_BUILDX) inspect $(DOCKER_BUILDX_BUILDER) || $(DOCKER_BUILDX) bootstrap

build:
	# Build the Docker image using Buildx
	$(DOCKER_BUILDX) build --builder $(DOCKER_BUILDX_BUILDER) \
		--platform $(DOCKER_BUILDX_PLATFORMS) \
		--build-arg MIX_ENV=$(MIX_ENV) \
		--build-arg APP_DIR=$(APP_DIR) \
		--build-arg APP_NAME=$(APP_NAME) \
		--build-arg TARGETPLATFORM=$(TARGETPLATFORM) \
		-t $(DOCKER_REGISTRY)/$(DOCKER_REPO):$(DOCKER_TAG) \
		--push .

push:
	# Push the Docker image to the registry (done as part of the build step)
	@echo "Image has been pushed to $(DOCKER_REGISTRY)/$(DOCKER_REPO):$(DOCKER_TAG)"

dev-run:
	# Run the Docker image locally
	docker run --rm \
	-e MIX_ENV=prod \
	-e HIVEFORGE_CONTROLLER_API_ENDPOINT=$(HIVEFORGE_CONTROLLER_API_ENDPOINT) \
	-e HIVEFORGE_CA_CERT_PATH=/hiveforge_agent/misc/certificates/ca-cert.pem \
	-v ./misc/certificates:/hiveforge_agent/misc/certificates:ro \
	$(DOCKER_REGISTRY)/$(DOCKER_REPO):$(DOCKER_TAG)

clean:
	# Clean up buildx builder
	$(DOCKER_BUILDX) rm $(DOCKER_BUILDX_BUILDER)
