#!/bin/bash
# ArgoCD Envsubst Plugin - Simplified for Bootstrap Purpose
# This plugin substitutes environment variables in Kubernetes manifests
# Values come from a ConfigMap created dynamically during deployment

set -euo pipefail

# Set HOME to a writable directory for helm
export HOME=$(mktemp -d /tmp/argocd-envsubst-home.XXXXXX)
trap "rm -rf $HOME" EXIT

# Function to log messages
log() {
    echo "[argocd-envsubst] $1" >&2
}

# Function to load values from ConfigMap
load_env_values() {
    # ConfigMap is the ONLY source - created dynamically by task deploy
    if [ -f "/envsubst-values/values" ]; then
        log "Loading values from ConfigMap"
        set -a  # Export all variables
        source "/envsubst-values/values"
        set +a
        return 0
    else
        # For testing only - allow running without ConfigMap
        if [ "${ARGOCD_ENVSUBST_STRICT:-true}" = "false" ]; then
            log "WARNING: ConfigMap not found, using environment variables (test mode)"
            return 0
        else
            log "ERROR: ConfigMap not found at /envsubst-values/values"
            log "The ConfigMap should be created by 'task deploy' from your local .env file"
            log "This ensures private values like domains and IPs are never committed to Git"
            return 1
        fi
    fi
}

# Function to substitute environment variables
substitute_env_vars() {
    local manifests="$1"
    
    # Extract all variable names
    local vars_found
    vars_found=$(echo "$manifests" | grep -oE '\$\{[a-zA-Z_][a-zA-Z0-9_]*(\}|:-)' | sed 's/\${//g' | sed 's/}//g' | sed 's/:-//g' | sort -u)
    
    if [ -z "$vars_found" ]; then
        log "No variables found in manifests"
        echo "$manifests"
        return 0
    fi
    
    log "Variables found: $(echo $vars_found | tr '\n' ' ')"
    
    # Build list of variables that exist in environment
    local vars_to_substitute=""
    local missing_vars=""
    
    for var in $vars_found; do
        if [ -n "${!var:-}" ]; then
            vars_to_substitute="$vars_to_substitute \$$var"
        else
            missing_vars="$missing_vars $var"
        fi
    done
    
    if [ -n "$missing_vars" ]; then
        log "WARNING: Variables not defined:$missing_vars"
    fi
    
    if [ -n "$vars_to_substitute" ]; then
        log "Substituting variables:$vars_to_substitute"
        # First pass: substitute only defined variables
        local result=$(echo "$manifests" | envsubst "$vars_to_substitute")
        
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
        log "No variables to substitute, processing defaults only"
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
    generate)
        log "Generating manifests with environment substitution"
        log "Working directory: $(pwd)"
        log "Files in directory: $(ls -la 2>&1 | head -5)"
        
        # More detailed debugging
        if [ ! -f "kustomization.yaml" ]; then
            log "WARNING: kustomization.yaml not found!"
            log "Checking for kustomization files:"
            find . -name "kustomization*.yaml" -o -name "Kustomization" 2>&1 | head -10
            log "All YAML files in current directory:"
            if ! ls -la *.yaml *.yml 2>/dev/null | head -20; then
                log "No YAML files in current directory (checking subdirectories)"
                log "YAML files in subdirectories:"
                find . -name "*.yaml" -o -name "*.yml" | grep -v "^\\./\\." | head -20 || log "No YAML files found anywhere"
            fi
            
            # Check parent directories
            log "Checking parent directory:"
            ls -la ../ | head -10
            log "Checking if we're in a subdirectory:"
            basename "$(pwd)"
        fi
        
        # Load values from ConfigMap
        if ! load_env_values; then
            exit 1
        fi
        
        # Generate manifests
        if [ -f "kustomization.yaml" ]; then
            log "Building with kustomize"
            # Capture both stdout and stderr separately
            kustomize_output=$(mktemp)
            kustomize_error=$(mktemp)
            if kustomize build . --enable-helm >"$kustomize_output" 2>"$kustomize_error"; then
                manifests=$(cat "$kustomize_output")
                rm -f "$kustomize_output" "$kustomize_error"
            else
                log "ERROR: kustomize build failed"
                if [ -s "$kustomize_error" ]; then
                    log "STDERR output:"
                    cat "$kustomize_error" >&2
                fi
                if [ -s "$kustomize_output" ]; then
                    log "STDOUT output (first 500 chars):"
                    head -c 500 "$kustomize_output" >&2
                fi
                rm -f "$kustomize_output" "$kustomize_error"
                exit 1
            fi
        else
            # Check for raw YAML files (including subdirectories)
            yaml_files=$(find . -name "*.yaml" -o -name "*.yml" | grep -v "^\\./\\." | sort)
            if [ -n "$yaml_files" ]; then
                log "Processing raw YAML files"
                manifests=""
                for file in $yaml_files; do
                    log "Processing file: $file"
                    if [ -n "$manifests" ]; then
                        manifests="$manifests
---
$(cat "$file")"
                    else
                        manifests=$(cat "$file")
                    fi
                done
            else
                log "No YAML files found in directory"
                # Return empty output - ArgoCD will handle this gracefully
                echo "---"
                exit 0
            fi
        fi
        
        # Substitute variables
        substitute_env_vars "$manifests"
        ;;
    *)
        log "Unknown command: $1"
        exit 1
        ;;
esac