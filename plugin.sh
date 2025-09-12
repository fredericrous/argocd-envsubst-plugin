#!/bin/bash
# ArgoCD Envsubst Plugin Main Script

set -euo pipefail

# Cache directory
CACHE_DIR="${ARGOCD_ENV_CACHE_DIR:-/tmp/argocd-envsubst-cache}"
CACHE_TTL="${ARGOCD_ENV_CACHE_TTL:-300}" # 5 minutes default
METRICS_FILE="/tmp/argocd-envsubst-metrics"

# Function to log messages
log() {
    echo "[argocd-envsubst] $1" >&2
}

# Function to find repository root
find_repo_root() {
    local current_path="${ARGOCD_APP_SOURCE_PATH:-.}"
    
    # If no path is set, try to find .git directory
    if [ "$current_path" = "." ]; then
        local dir="$PWD"
        while [ "$dir" != "/" ]; do
            if [ -d "$dir/.git" ] || [ -f "$dir/.env" ]; then
                echo "$dir"
                return 0
            fi
            dir=$(dirname "$dir")
        done
        echo "$PWD"
        return 0
    fi
    
    # Calculate how many levels up based on ARGOCD_APP_SOURCE_PATH
    local levels=$(echo "$current_path" | tr '/' '\n' | grep -v '^$' | wc -l)
    local repo_root="."
    for ((i=0; i<levels; i++)); do
        repo_root="../$repo_root"
    done
    
    # Normalize the path
    echo "$(cd "$repo_root" 2>/dev/null && pwd)" || echo "$repo_root"
}

# Function to load .env files
load_env_files() {
    local repo_root=$(find_repo_root)
    local env_loaded=false
    
    # Check for ENV_FILE environment variable
    if [ -n "${ENV_FILE:-}" ]; then
        local env_file="$ENV_FILE"
        
        # Handle absolute paths from repo root
        if [[ "$env_file" =~ ^/ ]]; then
            env_file="${repo_root}${env_file}"
        fi
        
        if [ -f "$env_file" ]; then
            log "Loading environment from: $env_file"
            set -a  # Export all variables
            source "$env_file"
            set +a
            env_loaded=true
        else
            log "WARNING: ENV_FILE specified but not found: $env_file"
        fi
    else
        # Load environment files in order of precedence
        
        # 1. Check for environment-specific file
        if [ -n "${ENVIRONMENT:-}" ] && [ -f "${repo_root}/environments/${ENVIRONMENT}.env" ]; then
            log "Loading environment: ${ENVIRONMENT}"
            set -a
            source "${repo_root}/environments/${ENVIRONMENT}.env"
            set +a
            env_loaded=true
        fi
        
        # 2. Load global .env from repo root
        if [ -f "${repo_root}/.env" ]; then
            log "Loading global .env"
            set -a
            source "${repo_root}/.env"
            set +a
            env_loaded=true
        fi
        
        # 3. Load app-specific .env (overrides global)
        if [ -f ".env" ]; then
            log "Loading app-specific .env"
            set -a
            source ".env"
            set +a
            env_loaded=true
        fi
    fi
    
    if [ "$env_loaded" = false ]; then
        log "INFO: No .env files found, using only existing environment variables"
    fi
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
    local vars_found=$(echo "$manifests" | grep -oE '\$\{[a-zA-Z_][a-zA-Z0-9_]*' | sed 's/\${//g' | sort -u)
    
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
        
        # Load .env files first
        load_env_files
        
        start_time=$(date +%s.%N 2>/dev/null || date +%s)
        
        # Calculate cache key based on directory content
        cache_key=$(find . -type f \( -name "*.yaml" -o -name "*.yml" \) -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)
        cache_file="$CACHE_DIR/$cache_key"
        
        # Check cache
        if [ -f "$cache_file" ] && [ $(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0))) -lt $CACHE_TTL ]; then
            log "Using cached manifests"
            update_metric "argocd_envsubst_cache_hits_total" 1
            manifests=$(cat "$cache_file")
        else
            # Generate manifests based on what's available
            if [ -f "kustomization.yaml" ]; then
                log "Building with kustomize"
                manifests=$(kustomize build . --enable-helm)
            elif ls *.yaml 2>/dev/null | grep -q . || ls *.yml 2>/dev/null | grep -q .; then
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
            
            # Create cache directory if needed
            mkdir -p "$CACHE_DIR"
            # Save to cache
            echo "$manifests" > "$cache_file"
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