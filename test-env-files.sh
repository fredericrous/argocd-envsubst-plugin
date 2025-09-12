#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Testing .env file support...${NC}"

# Create test directory structure
TEST_ROOT=$(mktemp -d)
export ARGOCD_APP_SOURCE_PATH="manifests/apps/test-app"

# Create directory structure
mkdir -p "$TEST_ROOT/manifests/apps/test-app"
mkdir -p "$TEST_ROOT/environments"

# Create global .env
cat > "$TEST_ROOT/.env" <<EOF
DOMAIN=example.com
NAMESPACE=default
LOG_LEVEL=info
GLOBAL_VAR=from-root
EOF

# Create environment-specific .env
cat > "$TEST_ROOT/environments/production.env" <<EOF
DOMAIN=prod.example.com
LOG_LEVEL=warning
ENV_VAR=from-production
EOF

# Create app-specific .env
cat > "$TEST_ROOT/manifests/apps/test-app/.env" <<EOF
LOG_LEVEL=debug
APP_VAR=from-app
EOF

# Create test manifest
cat > "$TEST_ROOT/manifests/apps/test-app/config.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-config
  namespace: \${NAMESPACE}
data:
  domain: \${DOMAIN}
  log_level: \${LOG_LEVEL}
  global_var: \${GLOBAL_VAR}
  env_var: \${ENV_VAR:-not-set}
  app_var: \${APP_VAR}
  missing_var: \${MISSING_VAR:-default-value}
EOF

# Create kustomization.yaml
cat > "$TEST_ROOT/manifests/apps/test-app/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- config.yaml
EOF

cd "$TEST_ROOT/manifests/apps/test-app"

echo -e "\n${YELLOW}Test 1: Loading without environment (should use global + app .env)${NC}"
output=$(./plugin.sh generate 2>&1)
if echo "$output" | grep -q "domain: example.com" && \
   echo "$output" | grep -q "log_level: debug" && \
   echo "$output" | grep -q "global_var: from-root" && \
   echo "$output" | grep -q "app_var: from-app" && \
   echo "$output" | grep -q "env_var: not-set" && \
   echo "$output" | grep -q "missing_var: default-value"; then
    echo -e "${GREEN}✅ PASS${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
    echo "Output:"
    echo "$output"
    exit 1
fi

echo -e "\n${YELLOW}Test 2: Loading with ENVIRONMENT=production${NC}"
ENVIRONMENT=production output=$(./plugin.sh generate 2>&1)
if echo "$output" | grep -q "domain: prod.example.com" && \
   echo "$output" | grep -q "log_level: debug" && \
   echo "$output" | grep -q "env_var: from-production"; then
    echo -e "${GREEN}✅ PASS${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
    echo "Output:"
    echo "$output"
    exit 1
fi

echo -e "\n${YELLOW}Test 3: Using ENV_FILE${NC}"
# Create custom env file
cat > "$TEST_ROOT/custom.env" <<EOF
DOMAIN=custom.example.com
CUSTOM_VAR=from-custom
EOF

ENV_FILE="/custom.env" output=$(./plugin.sh generate 2>&1)
if echo "$output" | grep -q "domain: custom.example.com"; then
    echo -e "${GREEN}✅ PASS${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
    echo "Output:"
    echo "$output"
    exit 1
fi

echo -e "\n${YELLOW}Test 4: Relative ENV_FILE${NC}"
cat > "$TEST_ROOT/manifests/apps/test-app/local.env" <<EOF
DOMAIN=local.example.com
EOF

ENV_FILE="local.env" output=$(./plugin.sh generate 2>&1)
if echo "$output" | grep -q "domain: local.example.com"; then
    echo -e "${GREEN}✅ PASS${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
    echo "Output:"
    echo "$output"
    exit 1
fi

# Cleanup
cd /
rm -rf "$TEST_ROOT"

echo -e "\n${GREEN}All .env file tests passed!${NC}"