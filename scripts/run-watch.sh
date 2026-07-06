#!/usr/bin/env bash
# Runs continuously in this terminal (foreground), checking Drive on the
# interval set in config.json. Ctrl+C to stop. Linux/macOS.
# For a background service that survives closing the terminal / reboots,
# use scripts/start-service.sh (PM2) instead.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINNED="$REPO_ROOT/.runtime/python_path.txt"
PYTHON_BIN="python3"
[ -f "$PINNED" ] && PYTHON_BIN="$(cat "$PINNED")"

echo "============================================"
echo " Drive Auto-Fetcher - Watch Mode (foreground)"
echo " Ctrl+C to stop."
echo "============================================"
echo ""
"$PYTHON_BIN" "$REPO_ROOT/src/drive_fetcher.py" --watch
