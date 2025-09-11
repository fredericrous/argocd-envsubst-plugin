# ArgoCD Envsubst Plugin

A Config Management Plugin for ArgoCD that provides dynamic environment variable substitution for Kustomize manifests.

## Features

- 🔍 **Auto-detection**: Automatically finds `${VARIABLE}` patterns in your manifests
- 🔄 **Dynamic substitution**: Only substitutes variables that exist in the environment
- ⚠️  **Validation**: Warns about missing variables
- 🚀 **Zero configuration**: No need to maintain lists of variables
- 🔒 **Secure**: Only substitutes variables you explicitly provide
- 📊 **Metrics**: Prometheus-compatible metrics endpoint
- 💾 **Caching**: Intelligent caching for improved performance
- 📁 **Flexible**: Supports both Kustomize and raw YAML files
- 🔤 **Case Support**: Handles uppercase, lowercase, and mixed-case variables

## Installation

### Option 1: Helm Chart

```bash
helm repo add fredericrous https://fredericrous.github.io/charts
helm install argocd-envsubst fredericrous/argocd-envsubst-plugin \
  --namespace argocd \
  --set envFrom[0].secretRef.name=argocd-env
```

### Option 2: Kustomize Patch

```bash
kubectl apply -k https://github.com/fredericrous/argocd-envsubst-plugin/kustomize
```

### Option 3: Manual Installation

1. Apply the ConfigMap plugin (for v1 plugins):
```bash
kubectl apply -f argocd-cm-plugin.yaml
```

2. Or install as sidecar (v2 plugin):
```bash
kubectl patch deployment argocd-repo-server -n argocd --patch-file argocd-repo-server-patch.yaml
```

## Usage

### 1. Create a Secret with Your Environment Variables

```bash
kubectl create secret generic argocd-env \
  --namespace argocd \
  --from-literal=CLUSTER_DOMAIN=example.com \
  --from-literal=VAULT_ADDR=http://vault:8200
```

Or from a `.env` file:
```bash
kubectl create secret generic argocd-env \
  --namespace argocd \
  --from-env-file=.env
```

### 2. Configure Your Application

The plugin must be explicitly specified in your Application manifest:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/myorg/myrepo
    targetRevision: main
    path: manifests/my-app
    # Explicitly specify the plugin
    plugin:
      name: envsubst
```

### 3. Use Variables in Your Manifests

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  domain: ${CLUSTER_DOMAIN}
  vault_url: ${VAULT_ADDR}
```

## Configuration

### Plugin Usage

The plugin must be explicitly enabled in your Application manifest. There is no auto-discovery - this follows ArgoCD best practices for predictable behavior.

```yaml
source:
  plugin:
    name: envsubst
```

### Environment Variables

Pass variables through:

1. **Secret reference** (recommended):
```yaml
envFrom:
- secretRef:
    name: argocd-env
```

2. **Direct values**:
```yaml
env:
  CLUSTER_DOMAIN: example.com
```

## Advanced Usage

### Custom Variable Patterns

The plugin supports standard shell variable syntax:
- `${VARIABLE}` - Basic substitution (uppercase, lowercase, mixed-case)
- `${VARIABLE:-default}` - With default value
- `${VARIABLE:?error}` - Fail if not set

### Performance Tuning

Configure caching behavior:
```yaml
env:
  ARGOCD_ENV_CACHE_DIR: "/tmp/argocd-envsubst-cache"
  ARGOCD_ENV_CACHE_TTL: "300"  # 5 minutes
```

### Metrics

The plugin exposes Prometheus metrics on port 9090:
- `argocd_envsubst_plugin_info` - Plugin version
- `argocd_envsubst_substitutions_total` - Total substitutions
- `argocd_envsubst_errors_total` - Total errors
- `argocd_envsubst_cache_hits_total` - Cache hit rate
- `argocd_envsubst_processing_duration_seconds` - Processing time histogram

Access metrics:
```bash
kubectl port-forward -n argocd deployment/argocd-repo-server 9090:9090
curl http://localhost:9090/metrics
```

### Debugging

Enable debug logging:
```yaml
env:
  PLUGIN_DEBUG: "true"
```

Check logs:
```bash
kubectl logs -n argocd deployment/argocd-repo-server -c envsubst-plugin
```

## Testing

The plugin includes comprehensive tests to ensure reliability:

### Unit Tests

Run the unit tests to verify basic functionality:

```bash
make test-unit
# or
./test.sh
```

Tests include:
- Basic variable substitution
- Missing variable handling
- Default value syntax (`${VAR:-default}`)
- Complex manifests with multiple variables
- Special characters in values
- Empty variable patterns
- Performance with large manifests

### Docker Tests

Test the containerized plugin:

```bash
make test-docker
# or
./test-docker.sh
```

### Manual Testing

1. **Test substitution logic**:
```bash
# Create test files
cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- test.yaml
EOF

cat > test.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: test
data:
  domain: \${DOMAIN}
EOF

# Run plugin
export DOMAIN=example.com
./plugin.sh generate
```

2. **Test in Docker**:
```bash
docker run --rm \
  -v $(pwd):/workdir \
  -w /workdir \
  -e DOMAIN=example.com \
  ghcr.io/fredericrous/argocd-envsubst-plugin:latest \
  /usr/local/bin/argocd-envsubst-plugin generate
```

## Development

### Building the Plugin

```bash
# Build locally
make build

# Build for multiple platforms
make build-multi

# Push to registry
make push
```

### Testing Locally

```bash
# Run all tests
make test

# Run specific tests
make test-unit
make test-docker
```

## Security Considerations

- Only variables explicitly provided to the plugin are available for substitution
- The plugin runs with minimal privileges
- Sensitive values should be stored in Kubernetes secrets

## Contributing

1. Fork the repository
2. Create your feature branch
3. Test your changes
4. Submit a pull request

## License

MIT License - see LICENSE file for details