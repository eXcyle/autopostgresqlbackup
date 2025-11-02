IMAGE_NAME=autopostgresqlbackup
TAG=latest

DOCKER_REGISTRY=docker.io
DOCKER_USERNAME=jeroenkeizernl

GITHUB_REGISTRY=ghcr.io
GITHUB_USERNAME=jeroenkeizernl



.PHONY: test clean publish _build shell

pull:
	@echo "📥 Pulling latest source..."
	git pull

_build: pull clean
	@echo "🐳 Building Docker image..."
	docker build -t $(IMAGE_NAME):$(TAG) .

test: _build
	@echo "🚀 Running container..."
	docker run -d --name $(IMAGE_NAME) \
		-e PG_DBHOST=myserver \
		-e PG_USERNAME=postgres \
		-e PG_PASSWORD=mypassword \
		-e PG_DB_NAME="all" \
		-e TZ="Europe/Amsterdam" \
		-e CRON_SCHEDULE="40 4 * * *" \
		$(IMAGE_NAME):$(TAG)

publish: _build
	docker tag $(IMAGE_NAME):$(TAG) $(DOCKER_REGISTRY)/$(DOCKER_USERNAME)/$(IMAGE_NAME):$(TAG)
	docker tag $(IMAGE_NAME):$(TAG) $(GITHUB_REGISTRY)/$(GITHUB_USERNAME)/$(IMAGE_NAME):$(TAG)

	@echo "📤 Pushing to Docker Hub..."
	docker push $(DOCKER_REGISTRY)/$(DOCKER_USERNAME)/$(IMAGE_NAME):$(TAG)
	@echo "📤 Pushing to Github..."
	docker push $(GITHUB_REGISTRY)/$(GITHUB_USERNAME)/$(IMAGE_NAME):$(TAG)


clean:
	@echo "🧹 Removing container and image..."
	docker rm -f $(IMAGE_NAME)
	docker rmi -f $(IMAGE_NAME)
	docker builder prune -f

shell:
	@echo "🧑‍💻 Opening shell in container..."
	docker exec -it $(IMAGE_NAME) /bin/bash

