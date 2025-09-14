# ArgoCD Envsubst Plugin
FROM alpine:3.19

# Set shell with pipefail
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# Install required tools with pinned versions
RUN apk add --no-cache \
    bash=5.2.21-r0 \
    gettext=0.22.3-r0 \
    curl=8.12.1-r0 \
    bc=1.07.1-r4 \
    netcat-openbsd=1.226-r0

# Install kustomize
RUN curl -L https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.3.0/kustomize_v5.3.0_linux_amd64.tar.gz | \
    tar xz -C /usr/local/bin/

# Install helm
RUN curl -L https://get.helm.sh/helm-v3.16.3-linux-amd64.tar.gz | \
    tar xz && mv linux-amd64/helm /usr/local/bin/ && rm -rf linux-amd64

# Create plugin scripts
COPY plugin.sh /usr/local/bin/argocd-envsubst-plugin
COPY metrics-server.sh /usr/local/bin/argocd-envsubst-metrics
RUN chmod +x /usr/local/bin/argocd-envsubst-plugin /usr/local/bin/argocd-envsubst-metrics

# Plugin configuration
COPY plugin.yaml /home/argocd/cmp-server/config/plugin.yaml

# Copy startup script
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Create necessary directories (user 999 already exists in some Alpine images)
RUN mkdir -p /home/argocd/cmp-server/config && \
    mkdir -p /var/run/argocd && \
    mkdir -p /var/lock && \
    chown -R 999:999 /home/argocd /var/run/argocd /var/lock

# Run as non-root
USER 999

# Expose metrics port
EXPOSE 9090

ENTRYPOINT ["/usr/local/bin/start.sh"]