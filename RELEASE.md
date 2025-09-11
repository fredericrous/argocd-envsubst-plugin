# Release Process

This document describes the release process for the ArgoCD Envsubst Plugin.

## Prerequisites

1. **GitHub Token**: You need a personal access token with permissions to:
   - Push to the charts repository (fredericrous/charts)
   - Create releases
   - Push packages to ghcr.io

2. **Set up secrets** in the repository:
   - `CHARTS_REPO_TOKEN`: PAT with write access to fredericrous/charts

## Automated Release Process

The release is fully automated through GitHub Actions:

1. **Trigger a release**:
   ```bash
   # For patch release (1.0.0 -> 1.0.1)
   make release-patch
   
   # For minor release (1.0.0 -> 1.1.0)
   make release-minor
   
   # For major release (1.0.0 -> 2.0.0)
   make release-major
   ```

   Or manually via GitHub:
   - Go to Actions → Bump Version
   - Click "Run workflow"
   - Select version type
   - Click "Run workflow"

2. **What happens automatically**:
   - Version numbers updated in Chart.yaml
   - Documentation updated with new version
   - Git tag created and pushed
   - Docker image built for multiple platforms (amd64, arm64)
   - Docker image pushed to ghcr.io
   - Helm chart packaged
   - Helm chart published to https://fredericrous.github.io/charts
   - GitHub release created with installation instructions

## Manual Release (if needed)

1. **Update versions**:
   ```bash
   # Update Chart version
   sed -i 's/^version: .*/version: X.Y.Z/' helm/Chart.yaml
   sed -i 's/^appVersion: .*/appVersion: vX.Y.Z/' helm/Chart.yaml
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

### 2. Helm Chart Release
- Updates image tag in values.yaml
- Packages the Helm chart
- Publishes to https://fredericrous.github.io/charts
- Updates the Helm repository index

### 3. GitHub Release
- Creates a release with:
  - Auto-generated changelog
  - Installation instructions
  - Links to Docker image and Helm chart

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
2. Test the Helm installation:
   ```bash
   helm repo update
   helm search repo fredericrous/argocd-envsubst-plugin
   ```
3. Monitor for any issues

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