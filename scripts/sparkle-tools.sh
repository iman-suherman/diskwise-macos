#!/usr/bin/env bash
# Resolve Sparkle release utilities (generate_appcast, sign_update, generate_keys).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.7.0}"
TOOLS_DIR="$ROOT_DIR/.sparkle-tools"
TARBALL="$TOOLS_DIR/Sparkle-${SPARKLE_VERSION}.tar.xz"

ensure_sparkle_tools() {
  if [[ -x "$TOOLS_DIR/bin/generate_appcast" ]]; then
    return 0
  fi

  mkdir -p "$TOOLS_DIR"
  if [[ ! -f "$TARBALL" ]]; then
    echo "==> Downloading Sparkle ${SPARKLE_VERSION} tools"
    curl -fsSL \
      "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
      -o "$TARBALL"
  fi

  tar -xJf "$TARBALL" -C "$TOOLS_DIR"
}

ensure_sparkle_tools
export SPARKLE_BIN_DIR="$TOOLS_DIR/bin"
