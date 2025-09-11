.PHONY: build test push release help

IMAGE_REGISTRY ?= ghcr.io
IMAGE_NAME ?= fredericrous/argocd-envsubst-plugin
IMAGE_TAG ?= latest
PLATFORMS ?= linux/amd64,linux/arm64

help: ## Show this help
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*##"; printf "\033[36m\033[0m"} /^[a-zA-Z_-]+:.*?##/ { printf "  %-20s %s\n", $$1, $$2 } /^##@/ { printf "\n%s\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Development

test: ## Run all tests
	@echo "Running unit tests..."
	@chmod +x test.sh && ./test.sh

test-unit: ## Run unit tests only
	@chmod +x test.sh && ./test.sh

test-docker: ## Run Docker tests
	@chmod +x test-docker.sh && ./test-docker.sh

lint: ## Lint Helm chart
	helm lint helm

template: ## Render Helm chart
	helm template test helm --values helm/values.yaml

##@ Build

build: ## Build Docker image locally
	docker build -t $(IMAGE_REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG) .

build-multi: ## Build for multiple platforms
	docker buildx build --platform=$(PLATFORMS) -t $(IMAGE_REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG) .

##@ Release

push: ## Push Docker image
	docker push $(IMAGE_REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

push-multi: ## Build and push multi-platform image
	docker buildx build --platform=$(PLATFORMS) -t $(IMAGE_REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG) --push .

package-chart: ## Package Helm chart
	helm package helm --destination .deploy/

release-patch: ## Create a patch release (X.Y.Z -> X.Y.Z+1)
	gh workflow run bump-version.yml -f version=patch

release-minor: ## Create a minor release (X.Y.Z -> X.Y+1.0)
	gh workflow run bump-version.yml -f version=minor

release-major: ## Create a major release (X.Y.Z -> X+1.0.0)
	gh workflow run bump-version.yml -f version=major

release-notes: ## Generate release notes
	@echo "## ArgoCD Envsubst Plugin v$(VERSION)"
	@echo ""
	@echo "### Installation"
	@echo ""
	@echo "#### Helm"
	@echo '```bash'
	@echo "helm repo add fredericrous https://fredericrous.github.io/charts"
	@echo "helm repo update"
	@echo "helm install argocd-envsubst fredericrous/argocd-envsubst-plugin --version $(VERSION)"
	@echo '```'
	@echo ""
	@echo "#### Docker"
	@echo '```bash'
	@echo "docker pull $(IMAGE_REGISTRY)/$(IMAGE_NAME):v$(VERSION)"
	@echo '```'

##@ Utilities

clean: ## Clean generated files
	rm -rf .deploy/
	rm -f test.yaml kustomization.yaml output.yaml

version: ## Show current version from Chart
	@grep '^version:' helm/Chart.yaml | awk '{print $$2}'