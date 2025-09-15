# ArgoCD Envsubst Plugin

A Config Management Plugin for ArgoCD that provides dynamic environment variable substitution for Kustomize manifests.

## Features

- 🔍 **Auto-detection**: Automatically finds `${VARIABLE}` patterns in your manifests
- 🔄 **Dynamic substitution**: Only substitutes variables that exist in the ConfigMap
- ⚠️  **Validation**: Warns about missing variables
- 🚀 **Zero configuration**: No need to maintain lists of variables
- 🔒 **Secure**: Only substitutes variables from the mounted ConfigMap
- 📊 **Metrics**: Prometheus-compatible metrics endpoint
- 💾 **Caching**: Intelligent caching for improved performance
- 📁 **Flexible**: Supports both Kustomize and raw YAML files
- 🔤 **Case Support**: Handles uppercase, lowercase, and mixed-case variables
- 📦 **ConfigMap Support**: Reads values from mounted argocd-envsubst-values ConfigMap

## Installation

### Configure as Sidecar in ArgoCD Helm Values

Add the plugin as a sidecar container in your ArgoCD Helm values:

```yaml
repoServer:
  extraContainers:
    - name: envsubst
      image: ghcr.io/fredericrous/argocd-envsubst-plugin:3.0.6
      command: ["/usr/local/bin/start.sh"]
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 200m
          memory: 256Mi
      volumeMounts:
        - mountPath: /var/run/argocd
          name: var-files
        - mountPath: /home/argocd/cmp-server/config
          name: cmp-server-config
        - mountPath: /tmp
          name: cmp-tmp
        - mountPath: /envsubst-values
          name: envsubst-values
          readOnly: true
  volumes:
    - name: cmp-server-config
      configMap:
        name: argocd-envsubst-plugin-config
    - name: cmp-tmp
      emptyDir: {}
    - name: envsubst-values
      configMap:
        name: argocd-envsubst-values
        optional: true
```

Then create the plugin configuration:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-envsubst-plugin-config
  namespace: argocd
data:
  plugin.yaml: |
    apiVersion: argoproj.io/v1alpha1
    kind: ConfigManagementPlugin
    metadata:
      name: argocd-envsubst-plugin
    spec:
      generate:
        command: ["/usr/local/bin/argocd-envsubst-plugin"]
        args: ["generate"]
EOF
```

## Usage

### 1. Create a ConfigMap with Your Environment Variables

```bash
kubectl create configmap argocd-envsubst-values \
  --namespace argocd \
  --from-literal=ARGO_CLUSTER_DOMAIN=example.com \
  --from-literal=ARGO_VAULT_ADDR=http://vault:8200
```

Or from your filtered environment file:
```bash
# Filter only ARGO_ prefixed variables
grep "^ARGO_" .env > /tmp/argo-values.env
kubectl create configmap argocd-envsubst-values \
  --namespace argocd \
  --from-env-file=/tmp/argo-values.env
```

### 2. Configure Your Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/your-org/your-repo
    targetRevision: main
    path: manifests/my-app
    plugin:
      name: envsubst
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
```

### 3. Use Variables in Your Manifests

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  domain: ${ARGO_CLUSTER_DOMAIN}
  vault_url: ${ARGO_VAULT_ADDR}
```

## ConfigMap and ExternalSecret Support

The plugin reads environment variables from two sources for resilience:

### ConfigMap Structure

The plugin expects a ConfigMap named `argocd-envsubst-values` in the `argocd` namespace:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-envsubst-values
  namespace: argocd
data:
  values: |-
    ARGO_DOMAIN=example.com
    ARGO_CLUSTER_NAME=production
    ARGO_DB_HOST=postgres.example.com
    ARGO_REPLICAS=3
```

### Initial Setup

1. **Create the ConfigMap** from your environment file:
```bash
# Filter only ARGO_ prefixed variables
grep "^ARGO_" .env > /tmp/argo-values.env

# Create or update the ConfigMap
kubectl create configmap argocd-envsubst-values \
  --namespace argocd \
  --from-env-file=/tmp/argo-values.env \
  --dry-run=client -o yaml | kubectl apply -f -
```

2. **After deployment**, backup to Vault for resilience:
```bash
# This stores values in Vault at secret/argocd/env-values
./scripts/backup-argocd-values-to-vault.sh
```

3. **ExternalSecret** automatically syncs from Vault:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: argocd-envsubst-values-external
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: argocd-envsubst-values-external
  dataFrom:
    - extract:
        key: secret/argocd/env-values
```

### Value Sources

1. **Primary**: ConfigMap mounted at `/envsubst-values/values`
   - Used during initial deployment
   - Fast access, no external dependencies
   - Lost if etcd fails

2. **Fallback**: Secret mounted at `/envsubst-values-external/values`
   - Created by External Secrets Operator from Vault
   - Survives etcd failures
   - Automatically synced from Vault

Both sources are automatically mounted through the ArgoCD repo server deployment configuration.

### Variable Naming Convention

It's recommended to prefix your variables with `ARGO_` to clearly distinguish them from other environment variables and secrets:

```bash
# Good - clearly identifies ArgoCD template variables
ARGO_EXTERNAL_DOMAIN=example.com
ARGO_CLUSTER_NAME=production
ARGO_VAULT_ADDR=http://vault:8200

# Avoid - could conflict with system variables
DOMAIN=example.com
CLUSTER=production
```

## Variable Substitution Behavior

### Variable Name Format

The plugin recognizes environment variables matching the pattern: `[a-zA-Z_][a-zA-Z0-9_]*`

This means:
- Must start with a letter (a-z, A-Z) or underscore (_)
- Can contain letters, numbers, and underscores
- Cannot contain dots, hyphens, or other special characters

Examples:
- ✅ Valid: `DOMAIN`, `APP_NAME`, `_PRIVATE`, `VAR123`
- ❌ Invalid: `app-name`, `app.domain`, `123VAR`, `var-with-hyphen`

### Default Values

You can specify default values for variables that might not be set:

```yaml
replicas: ${REPLICAS:-3}
namespace: ${NAMESPACE:-default}
```

### Validation

The plugin will:
- ✅ Substitute variables that exist in the ConfigMap
- ⚠️  Warn about variables that are not defined
- 🔒 Preserve variables that don't exist (won't substitute with empty string)
- ❌ Exit with error if both ConfigMap and Secret are missing

## Limitations

### ConfigMap Size Limit

Kubernetes ConfigMaps have a **1MB size limit**. This includes all keys and values combined.

To estimate your ConfigMap size:
```bash
grep "^ARGO_" .env | wc -c
```

If you're approaching the limit:
1. Review and remove unused variables
2. Use shorter variable names
3. Consider splitting into multiple ConfigMaps (requires plugin modification)
4. Store large values in Vault and reference them via ExternalSecrets

## Advanced Features

### Caching

The plugin caches processed manifests for improved performance:
- Default TTL: 5 minutes
- Cache key: Based on manifest content hash
- Configurable via `ARGOCD_ENV_CACHE_TTL` environment variable
- Thread-safe with file locking to prevent race conditions

### Strict Mode

The plugin runs in strict mode by default, which requires either ConfigMap or Secret to be present:
- Default: `ARGOCD_ENVSUBST_STRICT=true` (recommended for production)
- To disable: `ARGOCD_ENVSUBST_STRICT=false` (only for testing)

In strict mode, the plugin will exit with an error if neither ConfigMap nor Secret is found.

### Metrics

Prometheus metrics are available at `/metrics`:
- `argocd_envsubst_substitutions_total`: Total number of substitutions
- `argocd_envsubst_cache_hits_total`: Cache hit count
- `argocd_envsubst_processing_duration_seconds`: Processing time histogram

## Troubleshooting

### Variables Not Being Substituted

1. Check the ConfigMap exists:
```bash
kubectl get configmap argocd-envsubst-values -n argocd -o yaml
```

2. Verify the variable is in the ConfigMap:
```bash
kubectl get configmap argocd-envsubst-values -n argocd -o jsonpath='{.data.values}' | grep YOUR_VARIABLE
```

3. Check plugin logs:
```bash
kubectl logs -n argocd deployment/argocd-repo-server -c envsubst
```

### Common Issues

**Issue**: "ERROR: No values found at /envsubst-values/values or /envsubst-values-external/values"
- **Solution**: The plugin now requires either ConfigMap or Secret to exist. Create the ConfigMap with:
  ```bash
  kubectl create configmap argocd-envsubst-values \
    --namespace argocd \
    --from-env-file=/tmp/argo-values.env
  ```

**Issue**: Variables showing as `${VARIABLE}` in deployed manifests
- **Solution**: The variable is not defined in either ConfigMap or Secret. Add it or use a default value

**Issue**: Values not updating after ConfigMap change
- **Solution**: Restart ArgoCD repo server: `kubectl rollout restart deployment/argocd-repo-server -n argocd`

**Issue**: ExternalSecret not syncing
- **Solution**: Check External Secrets Operator logs and ensure Vault path `secret/argocd/env-values` exists

## Security Considerations

- The plugin only reads from the mounted ConfigMap, not from arbitrary files
- Variables are validated to prevent shell injection
- Sensitive data should use Kubernetes Secrets, not ConfigMaps
- Use RBAC to control who can modify the ConfigMap

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

