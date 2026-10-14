#!/bin/bash
# build-release.sh — Build YouxPC v2 release tarball
#
# Produces: youxpc-{VERSION}-macos-arm64.tar.gz
# Contents:
#   youxpc                                    — MCP server binary (Swift, arm64)
#   youxpc-vision                             — Vision sidecar launcher (shell script)
#   YOUXPC-MCP.md                             — Agent instructions
#   recipes/*.json                           — Bundled recipes
#   vision-sidecar/server.py                 — Vision sidecar Python server
#   vision-sidecar/requirements.txt          — Python dependencies
#
# Usage:
#   ./scripts/build-release.sh               # Build release tarball
#   ./scripts/build-release.sh --debug       # Build debug tarball (faster)
#
# The Homebrew formula downloads this tarball and installs:
#   /opt/homebrew/bin/youxpc
#   /opt/homebrew/bin/youxpc-vision
#   /opt/homebrew/share/youxpc/YOUXPC-MCP.md
#   /opt/homebrew/share/youxpc/recipes/*.json
#   /opt/homebrew/share/youxpc/vision-sidecar/server.py
#   /opt/homebrew/share/youxpc/vision-sidecar/requirements.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Read version from Types.swift
VERSION=$(grep -o 'version = "[^"]*"' "$PROJECT_ROOT/Sources/YouxPC/Common/Types.swift" | head -1 | cut -d'"' -f2)
if [[ -z "$VERSION" ]]; then
    echo "ERROR: Could not read version from Types.swift" >&2
    exit 1
fi

CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then
    CONFIG="debug"
fi

# Verify version consistency across all files
PYTHON_VERSION=$(grep '__version__' "$PROJECT_ROOT/vision-sidecar/server.py" | head -1 | cut -d'"' -f2)
BASH_VERSION=$(grep '^VERSION=' "$PROJECT_ROOT/vision-sidecar/youxpc-vision" | cut -d'"' -f2)
if [[ "$VERSION" != "$PYTHON_VERSION" || "$VERSION" != "$BASH_VERSION" ]]; then
    echo "ERROR: Version mismatch!" >&2
    echo "  Types.swift:  $VERSION" >&2
    echo "  server.py:    $PYTHON_VERSION" >&2
    echo "  youxpc-vision: $BASH_VERSION" >&2
    exit 1
fi

# One fixed name, so that releases/latest/download/<name> always points at the newest build.
TARBALL_NAME="youxpc-macos-arm64.tar.gz"
STAGE_DIR="$PROJECT_ROOT/.build/${CONFIG}-stage"

echo "Building YouxPC v${VERSION} ($CONFIG)"
echo "========================================"

# Step 1: Build Swift binary
echo ""
echo "Step 1: Building Swift binary..."
cd "$PROJECT_ROOT"
swift build -c "$CONFIG" 2>&1

BINARY="$PROJECT_ROOT/.build/$CONFIG/youxpc"
if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: Binary not found at $BINARY" >&2
    exit 1
fi

# Verify it runs
"$BINARY" version
echo "  Binary: $BINARY ($(du -h "$BINARY" | awk '{print $1}'))"

# Step 2: Stage release files
echo ""
echo "Step 2: Staging release files..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/recipes"
mkdir -p "$STAGE_DIR/vision-sidecar"

# Binary (re-sign after copy — linker-signed adhoc signatures break on copy)
cp "$BINARY" "$STAGE_DIR/youxpc"
codesign -f -s - "$STAGE_DIR/youxpc"

# youxpc-vision launcher
cp "$PROJECT_ROOT/vision-sidecar/youxpc-vision" "$STAGE_DIR/youxpc-vision"
chmod +x "$STAGE_DIR/youxpc-vision"

# Agent instructions
cp "$PROJECT_ROOT/YOUXPC-MCP.md" "$STAGE_DIR/"

# Recipes
cp "$PROJECT_ROOT/recipes/"*.json "$STAGE_DIR/recipes/" 2>/dev/null || true

# Vision sidecar
cp "$PROJECT_ROOT/vision-sidecar/server.py" "$STAGE_DIR/vision-sidecar/"
cp "$PROJECT_ROOT/vision-sidecar/requirements.txt" "$STAGE_DIR/vision-sidecar/"

echo "  Staged files:"
ls -la "$STAGE_DIR/"
echo ""
echo "  Staged recipes:"
ls "$STAGE_DIR/recipes/" 2>/dev/null || echo "    (none)"
echo ""
echo "  Staged vision-sidecar:"
ls "$STAGE_DIR/vision-sidecar/"

# Step 3: Create tarball
echo ""
echo "Step 3: Creating tarball..."
cd "$STAGE_DIR"
tar czf "$PROJECT_ROOT/$TARBALL_NAME" ./*
echo "  Tarball: $PROJECT_ROOT/$TARBALL_NAME"
echo "  Size: $(du -h "$PROJECT_ROOT/$TARBALL_NAME" | awk '{print $1}')"

# Step 4: Compute SHA256
echo ""
echo "Step 4: SHA256..."
SHA256=$(shasum -a 256 "$PROJECT_ROOT/$TARBALL_NAME" | awk '{print $1}')
# install.sh checks the download against this file.
(cd "$PROJECT_ROOT" && shasum -a 256 "$TARBALL_NAME" > "$TARBALL_NAME.sha256")
echo "  sha256 \"$SHA256\""

# Step 5: Summary
echo ""
echo "========================================"
echo "Release: YouxPC v${VERSION}"
echo "Tarball: $TARBALL_NAME"
echo "SHA256:  $SHA256"
echo ""
echo "To install locally:"
echo "  tar xzf $TARBALL_NAME -C /tmp/youxpc-install"
echo "  cp /tmp/youxpc-install/youxpc /opt/homebrew/bin/"
echo "  cp /tmp/youxpc-install/youxpc-vision /opt/homebrew/bin/"
echo ""
echo "To create GitHub release:"
echo "  gh release create v${VERSION} $TARBALL_NAME $TARBALL_NAME.sha256 --title \"YouxPC v${VERSION}\""
echo "========================================"

# Cleanup
rm -rf "$STAGE_DIR"
