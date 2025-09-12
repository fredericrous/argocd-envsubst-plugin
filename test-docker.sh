#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Building Docker image for testing...${NC}"
docker build -t argocd-envsubst-plugin:test .

echo -e "\n${YELLOW}Testing Docker image...${NC}"

# Test directory
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# Create test files
cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- configmap.yaml
EOF

cat > deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: \${NAMESPACE:-default}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: app
        image: \${IMAGE_REGISTRY}/\${IMAGE_NAME}:\${IMAGE_TAG}
        env:
        - name: DATABASE_URL
          value: \${DATABASE_URL}
EOF

cat > configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: \${NAMESPACE:-default}
data:
  api_url: \${API_URL}
  log_level: \${LOG_LEVEL:-info}
  cluster_domain: \${CLUSTER_DOMAIN}
EOF

# Run tests
echo -e "\n${YELLOW}Test 1: Basic substitution${NC}"
output=$(docker run --rm \
  -v "$(pwd)":/workdir:ro \
  -w /workdir \
  --user $(id -u):$(id -g) \
  -e NAMESPACE=production \
  -e IMAGE_REGISTRY=ghcr.io \
  -e IMAGE_NAME=myorg/myapp \
  -e IMAGE_TAG=v1.2.3 \
  -e DATABASE_URL=postgres://db:5432/myapp \
  -e API_URL=https://api.example.com \
  -e CLUSTER_DOMAIN=example.com \
  --entrypoint /usr/local/bin/argocd-envsubst-plugin \
  argocd-envsubst-plugin:test \
  generate)

if echo "$output" | grep -q "namespace: production" && \
   echo "$output" | grep -q "image: ghcr.io/myorg/myapp:v1.2.3" && \
   echo "$output" | grep -q "value: postgres://db:5432/myapp" && \
   echo "$output" | grep -q "api_url: https://api.example.com" && \
   echo "$output" | grep -q "cluster_domain: example.com" && \
   echo "$output" | grep -q "log_level: info"; then
    echo -e "${GREEN}✅ PASS${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
    echo "Output:"
    echo "$output"
    exit 1
fi

echo -e "\n${YELLOW}Test 2: Missing variables with defaults${NC}"
output=$(docker run --rm \
  -v "$(pwd)":/workdir:ro \
  -w /workdir \
  --user $(id -u):$(id -g) \
  -e CLUSTER_DOMAIN=test.local \
  --entrypoint /usr/local/bin/argocd-envsubst-plugin \
  argocd-envsubst-plugin:test \
  generate)

if echo "$output" | grep -q "namespace: default" && \
   echo "$output" | grep -q "log_level: info" && \
   echo "$output" | grep -q "cluster_domain: test.local"; then
    echo -e "${GREEN}✅ PASS${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
    echo "Output:"
    echo "$output"
    exit 1
fi

echo -e "\n${YELLOW}Test 3: Raw YAML processing - no kustomization.yaml${NC}"
rm -f kustomization.yaml
output=$(docker run --rm \
  -v "$(pwd)":/workdir:ro \
  -w /workdir \
  --user $(id -u):$(id -g) \
  --entrypoint /usr/local/bin/argocd-envsubst-plugin \
  argocd-envsubst-plugin:test \
  generate 2>&1 || true)

if echo "$output" | grep -q "Processing raw YAML files" && \
   echo "$output" | grep -q "namespace: default" && \
   echo "$output" | grep -q "log_level: info"; then
    echo -e "${GREEN}✅ PASS${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
    echo "Expected raw YAML processing with defaults"
    echo "Output:"
    echo "$output"
    exit 1
fi

# Cleanup
cd /
rm -rf "$TEST_DIR"

echo -e "\n${GREEN}All Docker tests passed!${NC}"