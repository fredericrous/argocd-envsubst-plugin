#!/bin/bash
# Simple metrics server for ArgoCD Envsubst Plugin

set -euo pipefail

PORT="${METRICS_PORT:-9090}"
METRICS_FILE="/tmp/argocd-envsubst-metrics"

# Initialize metrics
echo "# HELP argocd_envsubst_plugin_info Plugin version information
# TYPE argocd_envsubst_plugin_info gauge
argocd_envsubst_plugin_info{version=\"1.0.0\"} 1" > "$METRICS_FILE"

echo "# HELP argocd_envsubst_substitutions_total Total number of variable substitutions
# TYPE argocd_envsubst_substitutions_total counter
argocd_envsubst_substitutions_total 0" >> "$METRICS_FILE"

echo "# HELP argocd_envsubst_errors_total Total number of errors
# TYPE argocd_envsubst_errors_total counter
argocd_envsubst_errors_total 0" >> "$METRICS_FILE"

echo "# HELP argocd_envsubst_cache_hits_total Total number of cache hits
# TYPE argocd_envsubst_cache_hits_total counter
argocd_envsubst_cache_hits_total 0" >> "$METRICS_FILE"

echo "# HELP argocd_envsubst_processing_duration_seconds Time taken to process manifests
# TYPE argocd_envsubst_processing_duration_seconds histogram
argocd_envsubst_processing_duration_seconds_bucket{le=\"0.01\"} 0
argocd_envsubst_processing_duration_seconds_bucket{le=\"0.1\"} 0
argocd_envsubst_processing_duration_seconds_bucket{le=\"0.5\"} 0
argocd_envsubst_processing_duration_seconds_bucket{le=\"1\"} 0
argocd_envsubst_processing_duration_seconds_bucket{le=\"5\"} 0
argocd_envsubst_processing_duration_seconds_bucket{le=\"+Inf\"} 0
argocd_envsubst_processing_duration_seconds_sum 0
argocd_envsubst_processing_duration_seconds_count 0" >> "$METRICS_FILE"

# Function to update metrics
update_metric() {
    local metric="$1"
    local value="$2"
    local temp_file="/tmp/metric_update_$$"
    
    awk -v metric="$metric" -v value="$value" '
        $1 == metric { $2 = $2 + value }
        { print }
    ' "$METRICS_FILE" > "$temp_file"
    
    mv "$temp_file" "$METRICS_FILE"
}

# Start HTTP server
echo "Starting metrics server on port $PORT"
while true; do
    {
        echo "HTTP/1.1 200 OK"
        echo "Content-Type: text/plain; version=0.0.4"
        echo "Cache-Control: no-cache"
        echo ""
        cat "$METRICS_FILE"
    } | nc -l -p "$PORT" -q 1 >/dev/null 2>&1 || true
done