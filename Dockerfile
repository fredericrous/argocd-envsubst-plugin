# ArgoCD Envsubst Plugin
FROM alpine:3.19

# Install required tools
RUN apk add --no-cache bash gettext curl bc netcat-openbsd

# Install kustomize
RUN curl -L https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.3.0/kustomize_v5.3.0_linux_amd64.tar.gz | \
    tar xz -C /usr/local/bin/

# Create plugin scripts
COPY plugin.sh /usr/local/bin/argocd-envsubst-plugin
COPY metrics-server.sh /usr/local/bin/argocd-envsubst-metrics
RUN chmod +x /usr/local/bin/argocd-envsubst-plugin /usr/local/bin/argocd-envsubst-metrics

# Plugin configuration
COPY plugin.yaml /home/argocd/cmp-server/config/plugin.yaml

# Copy startup script
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Run as non-root
USER 999

# Expose metrics port
EXPOSE 9090

ENTRYPOINT ["/usr/local/bin/start.sh"]