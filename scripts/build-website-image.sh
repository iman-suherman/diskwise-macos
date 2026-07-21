#!/usr/bin/env bash
# Build and push the DiskWise website image to GitHub Container Registry.
# Prefer: npm run deploy:website (uses suherman-net-infra helper).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE_DIR="$ROOT/website"
IMAGE_REPO="${WEBSITE_IMAGE:-ghcr.io/iman-suherman/diskwise-website}"
TAG="${WEBSITE_IMAGE_TAG:-${GITHUB_SHA:-$(git -C "$ROOT" rev-parse HEAD)}}"
SHORT_TAG="${TAG:0:12}"
PLATFORM="${WEBSITE_PLATFORM:-linux/amd64}"
REGISTRY_API_URL="${NEXT_PUBLIC_REGISTRY_API_URL:-https://diskwise-registry.suherman.net}"
DOWNLOAD_BASE="${NEXT_PUBLIC_DOWNLOAD_BASE_URL:-https://diskwise-download.suherman.net/downloads}"
APP_ID="${NEXT_PUBLIC_APP_ID:-diskwise-macos}"

if ! command -v docker >/dev/null 2>&1; then
  echo "build-website-image: docker is required" >&2
  exit 1
fi

echo "build-website-image: ${IMAGE_REPO}:${TAG} (${PLATFORM})"
docker buildx build \
  --platform "$PLATFORM" \
  --build-arg "NEXT_PUBLIC_REGISTRY_API_URL=${REGISTRY_API_URL}" \
  --build-arg "NEXT_PUBLIC_DOWNLOAD_BASE_URL=${DOWNLOAD_BASE}" \
  --build-arg "NEXT_PUBLIC_APP_ID=${APP_ID}" \
  --tag "${IMAGE_REPO}:${TAG}" \
  --tag "${IMAGE_REPO}:${SHORT_TAG}" \
  --tag "${IMAGE_REPO}:latest" \
  --push \
  -f "$SERVICE_DIR/Dockerfile" \
  "$SERVICE_DIR"

echo "build-website-image: pushed ${IMAGE_REPO}:${TAG}"
