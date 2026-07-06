#!/usr/bin/env bash
# Runs a single check-and-download pass, then exits. Linux/macOS.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINNED="$REPO_ROOT/.runtime/python_path.txt"
PYTHON_BIN="python3"
[ -f "$PINNED" ] && PYTHON_BIN="$(cat "$PINNED")"

echo "============================================"
echo " Drive Auto-Fetcher - Single Run"
echo "============================================"
echo "Checking Google Drive for new files..."
echo ""
"$PYTHON_BIN" "$REPO_ROOT/src/drive_fetcher.py"
echo ""
echo "Done! Check drive_fetcher.log for details."
