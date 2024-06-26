# Default arguments
MIX_ENV ?= prod
APP_DIR ?= /app
APP_NAME ?= hiveforge_controller
MIGRATIONS_NAME ?= hiveforge_database_migrations
DOCKER_BUILDX_PLATFORMS ?= linux/amd64,linux/arm64
DOCKER_REGISTRY ?= quay.io
DOCKER_REPO ?= lajos_nagy/hiveforge-controller
MIGRATIONS_DOCKER_REPO ?= lajos_nagy/hiveforge-database-migrations
# DOCKER_TAG=erlang-{version}-{YYYYMMDD}-{iteration}    DOCKER_TAG=erlang-27.0-20240623-7
DOCKER_TAG ?= latest
HIVEFORGE_CONTROLLER_CERTFILE ?= /hiveforge_controller/misc/certificates/server.crt
HIVEFORGE_CONTROLLER_KEYFILE ?= /hiveforge_controller/misc/certificates/server.key
HIVEFORGE_CONTROLLER_PORT ?= 4000
TLS_TERMINATION_METHOD ?= service

# Docker Buildx setup
DOCKER_BUILDX ?= docker buildx
DOCKER_BUILDX_BUILDER ?= multi-arch-builder

.PHONY: all buildx-setup build push clean

all: build build-migrations push push-migrations

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
		--build-arg PORT=$(HIVEFORGE_CONTROLLER_PORT) \
		-t $(DOCKER_REGISTRY)/$(DOCKER_REPO):$(DOCKER_TAG) \
		--push .

build-migrations:
	# Build the Docker image for running migrations using Buildx
	$(DOCKER_BUILDX) build --builder $(DOCKER_BUILDX_BUILDER) \
		--platform $(DOCKER_BUILDX_PLATFORMS) \
		--build-arg MIX_ENV=$(MIX_ENV) \
		--build-arg APP_DIR=$(APP_DIR) \
		--build-arg APP_NAME=$(APP_NAME) \
		--build-arg TARGETPLATFORM=$(TARGETPLATFORM) \
		--build-arg PORT=$(HIVEFORGE_CONTROLLER_PORT) \
		-t $(DOCKER_REGISTRY)/$(MIGRATIONS_DOCKER_REPO):$(DOCKER_TAG) \
		--push -f Dockerfile.migrations .

push:
	# Push the Docker image to the registry (done as part of the build step)
	@echo "Image has been pushed to $(DOCKER_REGISTRY)/$(DOCKER_REPO):$(DOCKER_TAG)"

push-migrations:
	# Push the Docker image for running migrations to the registry (done as part of the build-migrations step)
    @echo "Image has been pushed to $(DOCKER_REGISTRY)/$(MIGRATIONS_DOCKER_REPO):$(DOCKER_TAG)"

dev-run:
	# Run the Docker image locally
	docker run --rm -p $(HIVEFORGE_CONTROLLER_PORT):$(HIVEFORGE_CONTROLLER_PORT) \
	-e MIX_ENV=prod \
	-e HIVEFORGE_CONTROLLER_CERTFILE=$(HIVEFORGE_CONTROLLER_CERTFILE) \
	-e HIVEFORGE_CONTROLLER_KEYFILE=$(HIVEFORGE_CONTROLLER_KEYFILE) \
	-e TLS_TERMINATION_METHOD=$(TLS_TERMINATION_METHOD) \
	-v ./misc/certificates:/hiveforge_controller/misc/certificates:ro \
	$(DOCKER_REGISTRY)/$(DOCKER_REPO):$(DOCKER_TAG)

clean:
	# Clean up buildx builder
	$(DOCKER_BUILDX) rm $(DOCKER_BUILDX_BUILDER)
