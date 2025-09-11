# Changelog

All notable changes to the ArgoCD Envsubst Plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Support for lowercase and mixed-case variables (fixes critical bug where only uppercase variables worked)
- Support for raw YAML files without kustomization.yaml
- Prometheus metrics endpoint on port 9090 with comprehensive metrics
- Intelligent caching mechanism with configurable TTL (default 5 minutes)
- Input validation for security (escapes potentially dangerous characters)
- Health checks (liveness and readiness probes)
- MIT LICENSE file for enterprise adoption
- Comprehensive test suite including lowercase variable tests

### Changed
- Optimized to run kustomize only once (significant performance improvement)
- Improved error handling to be less strict (returns unchanged manifests instead of failing)
- Updated Dockerfile to include metrics server and required tools (bc, netcat)
- Enhanced plugin discovery to detect both kustomization.yaml and raw YAML files
- Improved security context with read-only filesystem

### Fixed
- Critical bug: Variable pattern regex now supports all case types (was uppercase-only)
- Double kustomize execution removed from plugin.yaml
- Error handling now gracefully handles missing variables

### Security
- Added input validation to prevent shell injection attacks
- Variables with dangerous characters are automatically escaped
- Running as non-root user (999) with minimal privileges

## [1.0.0] - Initial Release

### Added
- Basic environment variable substitution for Kustomize
- Dynamic variable detection
- ArgoCD Config Management Plugin v2 support
- Docker multi-platform builds (amd64, arm64)
- Helm chart for easy deployment
- GitHub Actions workflows for CI/CD