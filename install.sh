#!/bin/bash
# Installs YouxPC for the current user. No sudo, nothing outside ~/.local.
#
#   curl -fsSL https://raw.githubusercontent.com/Ar5en1c/youxpc/main/install.sh | bash
#
# What it does:
#   1. downloads the latest release (one Apple silicon binary and a few text files)
#   2. checks it against the checksum published next to it
#   3. puts `youxpc` in ~/.local/bin and its reference files in ~/.local/share/youxpc
#   4. prints the line that tells your agent about it
#
# Set YOUXPC_PREFIX to install somewhere other than ~/.local.
set -euo pipefail

REPO="Ar5en1c/youxpc"
ASSET="youxpc-macos-arm64.tar.gz"
PREFIX="${YOUXPC_PREFIX:-$HOME/.local}"
URL="${YOUXPC_DOWNLOAD_URL:-https://github.com/$REPO/releases/latest/download/$ASSET}"

fail() { echo "youxpc install: $1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "YouxPC runs on macOS only."
[[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ]] || fail "macOS 14 or later is needed."
[[ "$(uname -m)" == "arm64" ]] || fail "the download is for Apple silicon. On an Intel Mac, build from source: https://github.com/$REPO#install"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading $URL"
curl -fsSL "$URL" -o "$WORK/$ASSET" || fail "could not download the release."
curl -fsSL "$URL.sha256" -o "$WORK/$ASSET.sha256" || fail "could not download the checksum."
(cd "$WORK" && shasum -a 256 -c "$ASSET.sha256" >/dev/null) || fail "the download does not match its checksum. Nothing was installed."

mkdir -p "$WORK/unpacked" "$PREFIX/bin" "$PREFIX/share/youxpc"
tar -xzf "$WORK/$ASSET" -C "$WORK/unpacked"
install -m 755 "$WORK/unpacked/youxpc" "$PREFIX/bin/youxpc"
cp -R "$WORK/unpacked/YOUXPC-MCP.md" "$WORK/unpacked/recipes" "$PREFIX/share/youxpc/" 2>/dev/null || true

"$PREFIX/bin/youxpc" version || fail "the binary was installed but did not run."

cat <<DONE

Installed: $PREFIX/bin/youxpc

Tell your agent about it. For Claude Code:

  claude mcp add youxpc -- $PREFIX/bin/youxpc mcp

For other agents, add an MCP server whose command is "$PREFIX/bin/youxpc" with the argument "mcp".

The first time it is used, macOS asks for Accessibility permission for the app
your agent runs in. Check the setup at any time with:

  $PREFIX/bin/youxpc doctor

To remove it: rm -rf "$PREFIX/bin/youxpc" "$PREFIX/share/youxpc" ~/.youxpc
DONE
