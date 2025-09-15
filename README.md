# ArgoCD Envsubst Plugin

A simple Config Management Plugin for ArgoCD that substitutes environment variables in Kubernetes manifests while keeping private values out of Git.

## The Problem

GitOps requires everything in Git, but you don't want to commit:
- Domain names (e.g., `domain.fr`)
- IP addresses (e.g., `192.168.0.42`)
- Cluster-specific configurations

## The Solution

Use variables in your manifests (`${ARGO_EXTERNAL_DOMAIN}`) and provide real values at deployment time from a local `.env` file.

## Installation

Add the plugin as a sidecar in your ArgoCD Helm values:

```yaml
repoServer:
  extraContainers:
    - name: envsubst
      image: ghcr.io/fredericrous/argocd-envsubst-plugin:latest
      command: [/var/run/argocd/argocd-cmp-server]
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
      volumeMounts:
        - mountPath: /var/run/argocd
          name: var-files
        - mountPath: /home/argocd/cmp-server/plugins
          name: plugins
        - mountPath: /tmp
          name: cmp-tmp
        - mountPath: /home/argocd/cmp-server/config/plugin.yaml
          subPath: plugin.yaml
          name: envsubst-plugin-config
        - mountPath: /envsubst-values
          name: envsubst-values
          readOnly: true

  volumes:
    - name: envsubst-values
      configMap:
        name: argocd-envsubst-values  # Created by task deploy
```

## Usage

### 1. Set Up Your Environment

Create a `.env` file with your private values:

```bash
ARGO_EXTERNAL_DOMAIN=domain.fr
ARGO_NAS_VAULT_ADDR=http://192.168.0.42:8200
ARGO_CLUSTER_NAME=homelab
```

### 2. Deploy

The ConfigMap is created automatically:

```bash
task deploy
```

### 3. Use Variables in Manifests

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-config
data:
  domain: ${ARGO_EXTERNAL_DOMAIN}
  vault-addr: ${ARGO_NAS_VAULT_ADDR}
  cluster: ${ARGO_CLUSTER_NAME}
```

### 4. Configure ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
spec:
  source:
    plugin:
      name: envsubst
```

## How It Works

```
.env → task deploy → ConfigMap → Plugin → Substituted Manifests
```

1. Local `.env` contains your values (never in Git)
2. `task deploy` creates ConfigMap dynamically
3. Plugin reads ConfigMap and substitutes variables
4. ArgoCD deploys manifests with real values

## Key Points

- **Simple**: Just variable substitution, no complex features
- **Secure**: Private values never touch Git
- **Fast**: No external calls, just local file reads
- **Reliable**: One source of truth (ConfigMap)

## Troubleshooting

Check ConfigMap:
```bash
kubectl get cm argocd-envsubst-values -n argocd -o yaml
```

View logs:
```bash
kubectl logs -n argocd deployment/argocd-repo-server -c envsubst
```

## License

MIT
