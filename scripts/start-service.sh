#!/usr/bin/env bash
# (Re)starts the background PM2 service and registers it to auto-start on
# boot (systemd/launchd, via `pm2 startup`). Requires that installer.sh has
# already been run at least once (PM2 installed, config.json + token.json
# present). Linux/macOS.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pick up PM2 even if it only lives in the installer's self-contained runtime dirs.
export PATH="$REPO_ROOT/.runtime/node/bin:$REPO_ROOT/.runtime/npm-global/bin:$PATH"

if ! command -v pm2 >/dev/null 2>&1; then
    echo "PM2 not found. Run ./installer.sh first."
    exit 1
fi
if [ ! -f "$REPO_ROOT/config.json" ]; then
    echo "config.json not found. Run ./installer.sh first (or: python3 src/configure.py)."
    exit 1
fi
if [ ! -f "$REPO_ROOT/token.json" ]; then
    echo "token.json not found. Run ./installer.sh first to log in to Google."
    exit 1
fi

cd "$REPO_ROOT"
pm2 start ecosystem.config.js
pm2 save

STARTUP_CMD="$(pm2 startup 2>/dev/null | grep -E '^(sudo|env) ' || true)"
if [ -n "$STARTUP_CMD" ]; then
    eval "$STARTUP_CMD" || echo "Could not auto-register startup. Run the command PM2 printed above manually."
fi

echo ""
echo "Started. Useful commands:"
echo "  pm2 list"
echo "  pm2 logs drive-auto-fetcher"
echo "  pm2 restart drive-auto-fetcher"
