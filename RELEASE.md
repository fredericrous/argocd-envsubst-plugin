# Release Process

This document describes the release process for the ArgoCD Envsubst Plugin.

## Prerequisites

1. **Set up secrets** in the repository:
   - `CHARTS_REPO_TOKEN`: PAT with write access to fredericrous/charts (optional, for Helm chart updates)

## Automated Release Process

The release process follows a two-stage workflow:

### Stage 1: Docker Release (Automatic)

When you push a tag, the release workflow automatically:
1. Runs tests
2. Builds multi-platform Docker images (amd64, arm64)
3. Pushes images to ghcr.io with semantic version tags
4. Creates a GitHub release with release notes

### Stage 2: Helm Chart Update (Triggered by Release)

After the GitHub release is published:
1. The update-helm-chart workflow triggers automatically
2. Creates a PR in the charts repository with updated chart version
3. Updates appVersion and image tag in the chart

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
   - Helm chart PR created in charts repository

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