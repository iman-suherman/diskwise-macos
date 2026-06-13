#!/usr/bin/env bash
set -euo pipefail

# DiskWise — install Python 3 for fast disk scanning.
# Safe to run multiple times.

info() { printf '==> %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '! %s\n' "$*" >&2; }

find_python3() {
  local candidate
  for candidate in \
    /opt/homebrew/bin/python3 \
    /usr/local/bin/python3 \
    /usr/bin/python3 \
    /Library/Frameworks/Python.framework/Versions/Current/bin/python3 \
    /Library/Frameworks/Python.framework/Versions/3.13/bin/python3 \
    /Library/Frameworks/Python.framework/Versions/3.12/bin/python3 \
    /Library/Frameworks/Python.framework/Versions/3.11/bin/python3; do
    if [[ -x "$candidate" ]] && "$candidate" -c 'import sys; exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

echo ""
echo "DiskWise — Python 3 Setup"
echo "========================="
echo ""

if python_path="$(find_python3)"; then
  ok "Python is already installed: $("$python_path" --version 2>&1)"
  ok "Location: $python_path"
  echo ""
  echo "Return to DiskWise — you can scan drives now."
  echo ""
  exit 0
fi

info "Python 3 was not found. DiskWise uses Python for fast disk scanning."
echo ""

if command -v brew >/dev/null 2>&1; then
  info "Installing Python via Homebrew…"
  brew install python
elif [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  info "Installing Python via Homebrew…"
  brew install python
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
  info "Installing Python via Homebrew…"
  brew install python
else
  if ! xcode-select -p >/dev/null 2>&1; then
    info "Opening Xcode Command Line Tools installer…"
    xcode-select --install || true
    echo ""
    echo "After Command Line Tools finish, run this script again."
    echo ""
  fi

  warn "Homebrew was not found."
  echo ""
  echo "Choose one of these options:"
  echo "  1. Install Homebrew from https://brew.sh, then run this script again"
  echo "  2. Download the macOS installer from https://www.python.org/downloads/macos/"
  echo ""
  open "https://www.python.org/downloads/macos/" 2>/dev/null || true
  exit 1
fi

if python_path="$(find_python3)"; then
  ok "Python installed: $("$python_path" --version 2>&1)"
  ok "Location: $python_path"
  echo ""
  echo "Return to DiskWise — you can scan drives now."
  echo ""
  exit 0
fi

warn "Python is still not available."
echo "Try downloading the installer from https://www.python.org/downloads/macos/"
open "https://www.python.org/downloads/macos/" 2>/dev/null || true
exit 1
