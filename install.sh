#!/bin/bash
# Build the release binary and install it to the stable path that
# ~/.claude.json's lookin MCP points at. Run after changing the Swift code.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$HOME/.lookin-swift"

cd "$SCRIPT_DIR"
echo "Building release..."
swift build -c release

mkdir -p "$DEST_DIR"
cp "$SCRIPT_DIR/.build/release/lookin-swift" "$DEST_DIR/lookin-swift"
echo "Installed: $DEST_DIR/lookin-swift"

echo "Verifying..."
"$DEST_DIR/lookin-swift" --selftest >/dev/null && echo "self-test OK"
echo "Done. Restart Claude Code to pick up a new binary."
