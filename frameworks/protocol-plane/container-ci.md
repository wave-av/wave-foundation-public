# Container Deploy CI (Bridges layer)

Reusable GitHub Actions workflow pattern for building + publishing + deploying CF Containers in the [Protocol Plane](README.md) Bridges layer.

## Why this exists

Each bridge container (SRT/NDI/OMT/ffmpeg/Dante) has:
1. A Dockerfile to build into an OCI image
2. A target registry to publish to (Docker Hub canonical)
3. A wrangler.toml binding to bump after publish

Rather than every container repo open-coding the build + publish + deploy dance, wave-foundation publishes a reusable workflow that the bridge consumer instantiates per-container.

## Reusable workflow shape

`wave-foundation/.github/workflows/container-deploy.yml`:

```yaml
name: container-deploy

on:
  workflow_call:
    inputs:
      container_dir:
        type: string
        required: true
        description: "Subdir of the calling repo containing the Dockerfile (e.g. 'containers/srt')"
      image_name:
        type: string
        required: true
        description: "Docker Hub image name (e.g. 'wave-av/wave-srt-bridge')"
      worker_name:
        type: string
        required: true
        description: "wave-bridge-edge Worker that consumes this container binding"
      env:
        type: string
        required: true
        description: "Target env: 'staging' or 'production'"

    secrets:
      DOCKERHUB_TOKEN:
        required: true
      CLOUDFLARE_API_TOKEN:
        required: true

jobs:
  build-and-publish:
    runs-on: ubuntu-latest
    outputs:
      image_tag: ${{ steps.tag.outputs.tag }}
    steps:
      - uses: actions/checkout@<pinned-sha>
        with: { persist-credentials: false }
      - id: tag
        run: echo "tag=$(git rev-parse --short HEAD)" >> "$GITHUB_OUTPUT"
      - uses: docker/login-action@<pinned-sha>
        with:
          username: wave-av
          password: ${{ secrets.DOCKERHUB_TOKEN }}
      - uses: docker/setup-buildx-action@<pinned-sha>
      - uses: docker/build-push-action@<pinned-sha>
        with:
          context: ${{ inputs.container_dir }}
          platforms: linux/amd64,linux/arm64
          push: true
          tags: |
            ${{ inputs.image_name }}:${{ steps.tag.outputs.tag }}
            ${{ inputs.image_name }}:${{ inputs.env }}
          cache-from: type=registry,ref=${{ inputs.image_name }}:buildcache
          cache-to: type=registry,ref=${{ inputs.image_name }}:buildcache,mode=max

  deploy:
    needs: build-and-publish
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<pinned-sha>
        with: { persist-credentials: false }
      - uses: cloudflare/wrangler-action@<pinned-sha>
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          command: deploy --env=${{ inputs.env }} --var "${{ inputs.image_name }}_IMAGE:${{ inputs.image_name }}:${{ needs.build-and-publish.outputs.image_tag }}"
          workingDirectory: ""
```

(Pin SHAs at consume time — use `pinact` for auto-pinning per the wave-foundation gate.)

## Consumer shape (in wave-bridge-edge)

`wave-bridge-edge/.github/workflows/srt-deploy.yml`:

```yaml
name: srt deploy
on:
  push:
    branches: [master]
    paths:
      - 'containers/srt/**'
      - '.github/workflows/srt-deploy.yml'
  workflow_dispatch:

jobs:
  staging:
    if: github.ref == 'refs/heads/master'
    uses: wave-av/wave-foundation/.github/workflows/container-deploy.yml@v1
    with:
      container_dir: containers/srt
      image_name: docker.io/wave-av/wave-srt-bridge
      worker_name: wave-bridge-edge
      env: staging
    secrets:
      DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}

  production:
    needs: staging
    if: github.ref == 'refs/heads/master'
    uses: wave-av/wave-foundation/.github/workflows/container-deploy.yml@v1
    with:
      container_dir: containers/srt
      image_name: docker.io/wave-av/wave-srt-bridge
      worker_name: wave-bridge-edge
      env: production
    secrets:
      DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

Stage-gate: `production` needs `staging` (smoke must pass before prod publishes).

## Promotion model

The same image tag (= short SHA) flows through staging → production. Worker var `<image>_IMAGE` is bumped on each deploy. Rollback = bump var to the previous tag (no rebuild).

## Public-repo consume note

Because wave-bridge-edge is public and wave-foundation is private, the reusable workflow CAN be consumed if the wave-foundation `.github/workflows/container-deploy.yml` is moved into a separate **public** repo for that specific workflow OR if it's inlined into the consumer (per the public-repo `_checks.yml` pattern).

**Recommendation:** mirror this workflow to `wave-av/wave-foundation-public/.github/workflows/container-deploy.yml` once we set up that mirror repo. Until then, inline it in wave-bridge-edge under `.github/workflows/_container-deploy.yml` and consume locally. Same pattern as `_checks.yml`.

## Multi-arch builds

CF Containers supports both `linux/amd64` and `linux/arm64`. The build-push-action above produces a manifest list with both architectures. Wrangler deploy picks the right one at container-instance allocation time.

## Linked

- [Protocol Plane](README.md) — what's being deployed
- [Observability](observability.md) — sidecar Workers for log forwarding
- [Auth Token Model](auth-token-model.md) — JWT verification in deployed containers
- [Foundation gate](../README.md) — secret-scan + file-size enforcement for these workflows
