#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test directory
PLUGIN_DIR=$(dirname "$0")
PLUGIN_SCRIPT="$PLUGIN_DIR/plugin.sh"

# Disable strict mode for tests
export ARGOCD_ENVSUBST_STRICT=false

# Ensure plugin script exists and is executable
if [ ! -f "$PLUGIN_SCRIPT" ]; then
    echo -e "${RED}ERROR: plugin.sh not found at $PLUGIN_SCRIPT${NC}"
    exit 1
fi
chmod +x "$PLUGIN_SCRIPT"

# Cleanup function
cleanup() {
    rm -f kustomization.yaml test-*.yaml output.yaml
}
trap cleanup EXIT

# Test framework functions
test_start() {
    local test_name="$1"
    echo -e "\n${YELLOW}TEST:${NC} $test_name"
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_pass() {
    echo -e "${GREEN}✅ PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    local message="$1"
    echo -e "${RED}❌ FAIL${NC}: $message"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Expected to contain '$needle'}"
    
    if echo "$haystack" | grep -q "$needle"; then
        return 0
    else
        test_fail "$message"
        echo "Output was:"
        echo "$haystack"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Expected NOT to contain '$needle'}"
    
    if echo "$haystack" | grep -q "$needle"; then
        test_fail "$message"
        echo "Output was:"
        echo "$haystack"
        return 1
    else
        return 0
    fi
}

# Test 1: Basic variable substitution
test_start "Basic variable substitution"
cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- test-basic.yaml
EOF

cat > test-basic.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-basic
data:
  domain: \${CLUSTER_DOMAIN}
  url: \${APP_URL}
EOF

export CLUSTER_DOMAIN="example.com"
export APP_URL="https://app.example.com"

output=$("$PLUGIN_SCRIPT" generate 2>&1)
if assert_contains "$output" "domain: example.com" && \
   assert_contains "$output" "url: https://app.example.com"; then
    test_pass
fi

unset CLUSTER_DOMAIN APP_URL

# Test 1.5: Lowercase variable support
test_start "Lowercase and mixed-case variable substitution"
cat > test-lowercase.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-lowercase
data:
  lowercase: \${my_var}
  mixedCase: \${MyVar}
  camelCase: \${myVariable}
  uppercase: \${MY_VAR}
EOF

cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- test-lowercase.yaml
EOF

export my_var="lowercase_value"
export MyVar="mixed_value"
export myVariable="camel_value"
export MY_VAR="upper_value"

output=$("$PLUGIN_SCRIPT" generate 2>&1)
if assert_contains "$output" "lowercase: lowercase_value" && \
   assert_contains "$output" "mixedCase: mixed_value" && \
   assert_contains "$output" "camelCase: camel_value" && \
   assert_contains "$output" "uppercase: upper_value"; then
    test_pass
fi

unset my_var MyVar myVariable MY_VAR

# Test 2: Missing variable handling
test_start "Missing variable remains unchanged"
cat > test-missing.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-missing
data:
  present: \${PRESENT_VAR}
  missing: \${MISSING_VAR}
EOF

cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- test-missing.yaml
EOF

export PRESENT_VAR="I am here"

output=$("$PLUGIN_SCRIPT" generate 2>&1)
if assert_contains "$output" "present: I am here" && \
   assert_contains "$output" 'missing: ${MISSING_VAR}' "Missing variable should remain unchanged"; then
    test_pass
fi

unset PRESENT_VAR

# Test 3: Default value syntax
test_start "Default value syntax \${VAR:-default}"
cat > test-defaults.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-defaults
data:
  with_default: \${UNDEFINED_VAR:-default_value}
  with_env: \${DEFINED_VAR:-should_not_see_this}
EOF

cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- test-defaults.yaml
EOF

export DEFINED_VAR="actual_value"

output=$("$PLUGIN_SCRIPT" generate 2>&1)
if assert_contains "$output" "with_default: default_value" && \
   assert_contains "$output" "with_env: actual_value"; then
    test_pass
fi

unset DEFINED_VAR

# Test 4: Complex manifest with multiple variables
test_start "Complex manifest with multiple variables"
cat > test-complex.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: \${APP_NAME}
  namespace: \${NAMESPACE}
spec:
  replicas: 3
  selector:
    matchLabels:
      app: \${APP_NAME}
  template:
    metadata:
      labels:
        app: \${APP_NAME}
        version: \${VERSION:-v1.0.0}
    spec:
      containers:
      - name: \${APP_NAME}
        image: \${IMAGE_REGISTRY}/\${IMAGE_NAME}:\${IMAGE_TAG}
        env:
        - name: DATABASE_URL
          value: \${DATABASE_URL}
        - name: LOG_LEVEL
          value: \${LOG_LEVEL:-info}
EOF

cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- test-complex.yaml
EOF

export APP_NAME="myapp"
export NAMESPACE="production"
export IMAGE_REGISTRY="ghcr.io"
export IMAGE_NAME="fredericrous/myapp"
export IMAGE_TAG="v2.1.0"
export DATABASE_URL="postgres://localhost:5432/mydb"

output=$("$PLUGIN_SCRIPT" generate 2>&1)
if assert_contains "$output" "name: myapp" && \
   assert_contains "$output" "namespace: production" && \
   assert_contains "$output" "image: ghcr.io/fredericrous/myapp:v2.1.0" && \
   assert_contains "$output" "value: postgres://localhost:5432/mydb" && \
   assert_contains "$output" "value: info" && \
   assert_contains "$output" "version: v1.0.0"; then
    test_pass
fi

unset APP_NAME NAMESPACE IMAGE_REGISTRY IMAGE_NAME IMAGE_TAG DATABASE_URL

# Test 5: Special characters in values
test_start "Special characters in variable values"
cat > test-special.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-special
data:
  url: \${URL_WITH_PARAMS}
  path: \${PATH_WITH_SPACES}
  json: \${JSON_VALUE}
EOF

cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- test-special.yaml
EOF

export URL_WITH_PARAMS="https://example.com?foo=bar&baz=qux"
export PATH_WITH_SPACES="/path/with spaces/file.txt"
export JSON_VALUE='{"key": "value", "nested": {"foo": "bar"}}'

output=$("$PLUGIN_SCRIPT" generate 2>&1)
if assert_contains "$output" "url: https://example.com?foo=bar&baz=qux" && \
   assert_contains "$output" "path: /path/with spaces/file.txt" && \
   assert_contains "$output" 'json: {"key": "value", "nested": {"foo": "bar"}}'; then
    test_pass
fi

unset URL_WITH_PARAMS PATH_WITH_SPACES JSON_VALUE

# Test 6: Empty variable name handling
test_start "Empty variable pattern handling"
cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- test-empty.yaml
EOF

cat > test-empty.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-empty
data:
  empty: \${}
  valid: \${VALID_VAR}
EOF

export VALID_VAR="valid_value"

output=$("$PLUGIN_SCRIPT" generate 2>&1)
if assert_contains "$output" 'empty: ${}' && \
   assert_contains "$output" "valid: valid_value"; then
    test_pass
fi

unset VALID_VAR

# Test 11: Raw YAML files support
test_start "Raw YAML files without kustomization"
# Remove kustomization.yaml
rm -f kustomization.yaml

cat > deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: \${APP_NAME}
spec:
  replicas: \${REPLICAS:-3}
  template:
    spec:
      containers:
      - name: app
        image: \${IMAGE}
EOF

cat > service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: \${APP_NAME}-service
spec:
  selector:
    app: \${APP_NAME}
EOF

export APP_NAME="test-app"
export IMAGE="nginx:latest"

output=$("$PLUGIN_SCRIPT" generate 2>&1)
if assert_contains "$output" "name: test-app" && \
   assert_contains "$output" "replicas: 3" && \
   assert_contains "$output" "image: nginx:latest" && \
   assert_contains "$output" "name: test-app-service"; then
    test_pass
fi

unset APP_NAME IMAGE
rm -f deployment.yaml service.yaml

# Summary
echo -e "\n========================================="
echo -e "Test Summary:"
echo -e "  Total tests: $TESTS_RUN"
echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
echo -e "========================================="

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed!${NC}"
    exit 1
fi