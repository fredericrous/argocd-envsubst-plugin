#!/bin/sh
# Start metrics server in background
/usr/local/bin/argocd-envsubst-metrics &
# Start plugin server
exec /var/run/argocd/argocd-cmp-server