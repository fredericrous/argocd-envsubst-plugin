# Release Process

This document describes the release process for the ArgoCD Envsubst Plugin.

## Prerequisites

1. **Set up secrets** in the repository:
   - No additional secrets required for releases

## Automated Release Process

The release process follows a two-stage workflow:

### Stage 1: Docker Release (Automatic)

When you push a tag, the release workflow automatically:
1. Runs tests
2. Builds multi-platform Docker images (amd64, arm64)
3. Pushes images to ghcr.io with semantic version tags
4. Creates a GitHub release with release notes


## Creating a Release

1. **Tag and push**:
   ```bash
   # Create annotated tag
   git tag -a v1.0.1 -m "Release v1.0.1"
   
   # Push the tag
   git push origin v1.0.1
   ```

2. **What happens automatically**:
   - Tests run
   - Docker images built and pushed
   - GitHub release created

## Manual Release (if needed)

1. **Update versions**:
   ```bash
   # No version files to update - just tag and release
   ```

2. **Commit and tag**:
   ```bash
   git add .
   git commit -m "chore: bump version to vX.Y.Z"
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin main
   git push origin vX.Y.Z
   ```

3. **The workflow will trigger automatically on the new tag**

## Publishing Workflow

The `.github/workflows/release.yml` handles:

### 1. Docker Image Build & Push
- Builds multi-platform images (linux/amd64, linux/arm64)
- Tags with semantic versioning (vX.Y.Z, vX.Y, vX)
- Pushes to ghcr.io/fredericrous/argocd-envsubst-plugin

### 2. GitHub Release
- Creates a release with:
  - Auto-generated changelog
  - Installation instructions
  - Links to Docker image

## Versioning Strategy

We follow semantic versioning:
- **MAJOR**: Breaking changes to plugin behavior
- **MINOR**: New features, backwards compatible
- **PATCH**: Bug fixes and minor improvements

## Testing Before Release

1. **Test locally**:
   ```bash
   make test
   make build
   make lint
   ```

2. **Test in cluster**:
   ```bash
   # Build and load image
   make build IMAGE_TAG=test
   
   # Update ArgoCD to use test image
   kubectl set image deployment/argocd-repo-server \
     envsubst-plugin=ghcr.io/fredericrous/argocd-envsubst-plugin:test \
     -n argocd
   ```

## Post-Release

After release:
1. Update homelab to use the new version
2. Monitor for any issues

## Rollback

If issues are found:
1. Delete the problematic release and tag
2. Fix the issue
3. Create a new patch release

## Makefile Targets

Helper targets for releases:
```makefile
release-patch:
	gh workflow run bump-version.yml -f version=patch

release-minor:
	gh workflow run bump-version.yml -f version=minor

release-major:
	gh workflow run bump-version.yml -f version=major
```