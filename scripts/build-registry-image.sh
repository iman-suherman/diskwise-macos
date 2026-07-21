#!/usr/bin/env bash
# Build and push the DiskWise registry API image to GitHub Container Registry.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE_DIR="$ROOT/services/registry-api"
IMAGE_REPO="${REGISTRY_API_IMAGE:-ghcr.io/iman-suherman/diskwise-registry-api}"
TAG="${REGISTRY_API_IMAGE_TAG:-${GITHUB_SHA:-$(git -C "$ROOT" rev-parse HEAD)}}"
SHORT_TAG="${TAG:0:12}"
PLATFORM="${REGISTRY_API_PLATFORM:-linux/amd64}"

if ! command -v docker >/dev/null 2>&1; then
  echo "build-registry-image: docker is required" >&2
  exit 1
fi

echo "build-registry-image: ${IMAGE_REPO}:${TAG} (${PLATFORM})"
docker buildx build \
  --platform "$PLATFORM" \
  --tag "${IMAGE_REPO}:${TAG}" \
  --tag "${IMAGE_REPO}:${SHORT_TAG}" \
  --tag "${IMAGE_REPO}:latest" \
  --push \
  -f "$SERVICE_DIR/Dockerfile" \
  "$SERVICE_DIR"

echo "build-registry-image: pushed ${IMAGE_REPO}:${TAG}"
