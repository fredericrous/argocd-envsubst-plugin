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

# Create argocd user and necessary directories
RUN adduser -D -u 999 -g 999 argocd && \
    mkdir -p /home/argocd/cmp-server/config && \
    mkdir -p /var/run/argocd && \
    chown -R argocd:argocd /home/argocd /var/run/argocd

# Run as non-root
USER 999

# Expose metrics port
EXPOSE 9090

ENTRYPOINT ["/usr/local/bin/start.sh"]