#!/bin/bash
# ArgoCD Envsubst Plugin Main Script

set -euo pipefail

# Cache directory
CACHE_DIR="${ARGOCD_ENV_CACHE_DIR:-/tmp/argocd-envsubst-cache}"
CACHE_TTL="${ARGOCD_ENV_CACHE_TTL:-300}" # 5 minutes default
METRICS_FILE="/tmp/argocd-envsubst-metrics"
# Strict mode - fail if no ConfigMap/Secret found (default: true, set to false for tests)
STRICT_MODE="${ARGOCD_ENVSUBST_STRICT:-true}"

# Function to log messages
log() {
    echo "[argocd-envsubst] $1" >&2
}


# Function to load values from ConfigMap or ExternalSecret
load_env_values() {
    local loaded=false
    
    # Primary: Check if we have ConfigMap values mounted
    if [ -f "/envsubst-values/values" ]; then
        log "Loading values from mounted ConfigMap"
        set -a  # Export all variables
        source "/envsubst-values/values"
        set +a
        loaded=true
    fi
    
    # Fallback: Check if we have ExternalSecret values mounted
    # This would be created by External Secrets Operator after initial deployment
    if [ -f "/envsubst-values-external/values" ]; then
        if [ "$loaded" = true ]; then
            log "Loading additional values from ExternalSecret (fallback)"
        else
            log "Loading values from ExternalSecret (ConfigMap not found)"
        fi
        set -a  # Export all variables
        source "/envsubst-values-external/values"
        set +a
        loaded=true
    fi
    
    if [ "$loaded" = false ]; then
        if [ "$STRICT_MODE" = "true" ]; then
            log "ERROR: No values found at /envsubst-values/values or /envsubst-values-external/values"
            log "Either argocd-envsubst-values ConfigMap or argocd-envsubst-values-external Secret must exist"
            log ""
            log "To fix this, create a ConfigMap with your environment variables:"
            log "  kubectl create configmap argocd-envsubst-values \\"
            log "    --namespace argocd \\"
            log "    --from-env-file=/tmp/argo-values.env"
            log ""
            log "Or ensure the ExternalSecret is properly configured and syncing from Vault"
            log "To disable this check (not recommended for production), set ARGOCD_ENVSUBST_STRICT=false"
            exit 1
        else
            log "WARNING: No values found at /envsubst-values/values or /envsubst-values-external/values"
            log "Strict mode disabled - using only environment variables already present in the container"
        fi
    fi
    
    return 0
}

# Function to update metrics
update_metric() {
    local metric="$1"
    local value="$2"
    if [ -f "$METRICS_FILE" ]; then
        local temp_file="/tmp/metric_update_$$"
        awk -v metric="$metric" -v value="$value" '
            $1 == metric { $2 = $2 + value }
            { print }
        ' "$METRICS_FILE" > "$temp_file" 2>/dev/null || true
        mv "$temp_file" "$METRICS_FILE" 2>/dev/null || true
    fi
}

# Function to validate input for security
validate_value() {
    local value="$1"
    # Reject values with shell metacharacters that could be dangerous
    if [[ "$value" =~ [\;\|\&\$\`] ]]; then
        log "WARNING: Potentially dangerous characters detected in value, escaping"
        # Escape dangerous characters
        value=$(printf '%q' "$value")
    fi
    echo "$value"
}

# Function to extract and substitute variables
substitute_env_vars() {
    local manifests="$1"
    
    # Extract all variable names (just the name part, not the full ${} expression)
    # This regex matches both ${VAR} and ${VAR:-default} patterns
    local vars_found
    vars_found=$(echo "$manifests" | grep -oE '\$\{[a-zA-Z_][a-zA-Z0-9_]*(\}|:-)' | sed 's/\${\|}\|:-//g' | sort -u)
    
    if [ -z "$vars_found" ]; then
        log "INFO: No variables found in manifests"
        echo "$manifests"
        return 0
    fi
    
    log "Variables found in manifests: $(echo $vars_found | tr '\n' ' ')"
    
    # Build list of variables that exist in environment
    local vars_to_substitute=""
    local var_count=0
    
    for var in $vars_found; do
        if [ -n "${!var:-}" ]; then
            vars_to_substitute="$vars_to_substitute \$$var"
            ((var_count++))
        fi
    done
    
    if [ "$var_count" -gt 0 ]; then
        update_metric "argocd_envsubst_substitutions_total" "$var_count"
    fi
    
    if [ -n "$vars_to_substitute" ]; then
        log "Substituting defined variables: $vars_to_substitute"
        # First pass: substitute only defined variables, preserving undefined ones
        result=$(echo "$manifests" | envsubst "$vars_to_substitute")
        
        # Second pass: handle ${VAR:-default} syntax for undefined variables
        # Process line by line to handle defaults safely
        while IFS= read -r line; do
            # Process all ${VAR:-default} patterns in this line
            while [[ "$line" =~ \$\{([a-zA-Z_][a-zA-Z0-9_]*):-([^}]*)\} ]]; do
                full_pattern="${BASH_REMATCH[0]}"
                var_name="${BASH_REMATCH[1]}"
                default_value="${BASH_REMATCH[2]}"
                
                # Check if variable is defined
                if [ -z "${!var_name:-}" ]; then
                    # Replace with default value
                    line="${line//$full_pattern/$default_value}"
                else
                    # This shouldn't happen as we already substituted defined vars
                    line="${line//$full_pattern/${!var_name}}"
                fi
            done
            echo "$line"
        done <<< "$result"
    else
        log "INFO: No variables defined in environment, processing defaults only"
        # Just process default values
        while IFS= read -r line; do
            while [[ "$line" =~ \$\{([a-zA-Z_][a-zA-Z0-9_]*):-([^}]*)\} ]]; do
                full_pattern="${BASH_REMATCH[0]}"
                var_name="${BASH_REMATCH[1]}"
                default_value="${BASH_REMATCH[2]}"
                
                if [ -z "${!var_name:-}" ]; then
                    line="${line//$full_pattern/$default_value}"
                else
                    line="${line//$full_pattern/${!var_name}}"
                fi
            done
            echo "$line"
        done <<< "$manifests"
    fi
}

# Main execution
case "${1:-generate}" in
    init)
        log "Initializing envsubst plugin"
        ;;
    generate)
        log "Generating manifests with environment substitution"
        
        # Load values from ConfigMap
        load_env_values
        
        start_time=$(date +%s.%N 2>/dev/null || date +%s)
        
        # Create cache directory if needed
        mkdir -p "$CACHE_DIR"
        
        # Calculate cache key based on directory content
        cache_key=$(find . -type f \( -name "*.yaml" -o -name "*.yml" \) -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)
        cache_file="$CACHE_DIR/$cache_key"
        
        # Determine lock directory - use /var/lock if it exists and is writable, otherwise use temp dir
        if [ -d "/var/lock" ] && [ -w "/var/lock" ]; then
            lock_file="/var/lock/envsubst-cache-${cache_key}.lock"
        else
            # Use the same directory as the cache for lock files
            lock_file="$CACHE_DIR/envsubst-cache-${cache_key}.lock"
        fi
        
        # Initialize cache_hit variable
        cache_hit=false
        
        # Use file locking if available to prevent race conditions
        if command -v flock >/dev/null 2>&1; then
            exec 200>"$lock_file"
            flock -x 200
            
            # Check cache with lock held
            if [ -f "$cache_file" ] && [ $(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0))) -lt $CACHE_TTL ]; then
                log "Using cached manifests"
                update_metric "argocd_envsubst_cache_hits_total" 1
                manifests=$(cat "$cache_file")
                cache_hit=true
            fi
            
            # Release lock
            exec 200>&-
        else
            # No flock available (e.g., macOS), check cache without lock
            if [ -f "$cache_file" ] && [ $(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0))) -lt $CACHE_TTL ]; then
                log "Using cached manifests"
                update_metric "argocd_envsubst_cache_hits_total" 1
                manifests=$(cat "$cache_file")
                cache_hit=true
            fi
        fi
        
        if [ "$cache_hit" = false ]; then
            # Generate manifests based on what's available
            if [ -f "kustomization.yaml" ]; then
                log "Building with kustomize"
                # Initialize values_files variable
                values_files=""
                # Check if we have Helm charts referenced
                if grep -q "helmCharts:" kustomization.yaml 2>/dev/null; then
                    log "Helm charts detected, including CRDs"
                    # Set environment variable for Helm to include CRDs
                    export HELM_INCLUDE_CRDS=1
                    
                    # Process values files for environment variable substitution
                    # Find all valuesFile references in kustomization.yaml
                    values_files=$(grep -E "^\s*valuesFile:" kustomization.yaml | sed 's/.*valuesFile:\s*//')
                    
                    if [ -n "$values_files" ]; then
                        log "Processing Helm values files for variable substitution"
                        for values_file in $values_files; do
                            if [ -f "$values_file" ]; then
                                log "Substituting variables in $values_file"
                                # Create a temporary file with substituted values
                                temp_file="${values_file}.tmp"
                                envsubst < "$values_file" > "$temp_file"
                                # Replace the original file temporarily
                                mv "$values_file" "${values_file}.orig"
                                mv "$temp_file" "$values_file"
                            fi
                        done
                    fi
                fi
                
                # Build with kustomize
                manifests=$(kustomize build . --enable-helm)
                
                # Restore original values files if they were modified
                if [ -n "$values_files" ]; then
                    for values_file in $values_files; do
                        if [ -f "${values_file}.orig" ]; then
                            mv "${values_file}.orig" "$values_file"
                        fi
                    done
                fi
            elif compgen -G "*.yaml" >/dev/null || compgen -G "*.yml" >/dev/null; then
                log "Processing raw YAML files"
                manifests=""
                for file in *.yaml *.yml; do
                    [ -f "$file" ] || continue
                    if [ -n "$manifests" ]; then
                        manifests="$manifests
---
$(cat "$file")"
                    else
                        manifests=$(cat "$file")
                    fi
                done
            else
                log "ERROR: No YAML files found in directory"
                exit 1
            fi
            
            # Save to cache with lock if available
            if command -v flock >/dev/null 2>&1; then
                exec 200>"$lock_file"
                flock -x 200
                echo "$manifests" > "$cache_file"
                exec 200>&-
            else
                # No flock available, save without lock
                echo "$manifests" > "$cache_file"
            fi
        fi
        
        result=$(substitute_env_vars "$manifests")
        
        # Calculate duration and update metrics
        end_time=$(date +%s.%N 2>/dev/null || date +%s)
        duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0.1")
        
        # Update duration histogram (simplified)
        if (( $(echo "$duration < 0.01" | bc -l 2>/dev/null || echo 0) )); then
            update_metric "argocd_envsubst_processing_duration_seconds_bucket{le=\"0.01\"}" 1
        elif (( $(echo "$duration < 0.1" | bc -l 2>/dev/null || echo 0) )); then
            update_metric "argocd_envsubst_processing_duration_seconds_bucket{le=\"0.1\"}" 1
        elif (( $(echo "$duration < 0.5" | bc -l 2>/dev/null || echo 0) )); then
            update_metric "argocd_envsubst_processing_duration_seconds_bucket{le=\"0.5\"}" 1
        elif (( $(echo "$duration < 1" | bc -l 2>/dev/null || echo 0) )); then
            update_metric "argocd_envsubst_processing_duration_seconds_bucket{le=\"1\"}" 1
        elif (( $(echo "$duration < 5" | bc -l 2>/dev/null || echo 0) )); then
            update_metric "argocd_envsubst_processing_duration_seconds_bucket{le=\"5\"}" 1
        fi
        update_metric "argocd_envsubst_processing_duration_seconds_bucket{le=\"+Inf\"}" 1
        update_metric "argocd_envsubst_processing_duration_seconds_count" 1
        
        echo "$result"
        ;;
    *)
        log "Unknown command: $1"
        exit 1
        ;;
esac