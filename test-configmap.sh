#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Testing ConfigMap mode...${NC}"

# This test validates that the plugin works without a mounted ConfigMap
# The plugin should continue with environment variables only

# Create test directory
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# Create test manifest
cat > config.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-config
data:
  # These should be substituted from environment variables
  test_var: \${TEST_VAR}
  with_default: \${MISSING_VAR:-default-value}
EOF

# Create kustomization.yaml
cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- config.yaml
EOF

# Set environment variable
export TEST_VAR="test-value"

# Run plugin
echo -e "\n${YELLOW}Test: ConfigMap mode (no mounted ConfigMap)${NC}"
PLUGIN_SCRIPT="$OLDPWD/plugin.sh"
output=$("$PLUGIN_SCRIPT" generate 2>&1)

if echo "$output" | grep -q "test_var: test-value" && \
   echo "$output" | grep -q "with_default: default-value" && \
   echo "$output" | grep -q "WARNING: No values found"; then
    echo -e "${GREEN}✅ PASS${NC} - Plugin works without ConfigMap in test mode"
else
    echo -e "${RED}❌ FAIL${NC}"
    echo "Output:"
    echo "$output"
    exit 1
fi

# Cleanup
cd - > /dev/null
rm -rf "$TEST_DIR"

echo -e "\n${GREEN}ConfigMap mode test passed!${NC}"