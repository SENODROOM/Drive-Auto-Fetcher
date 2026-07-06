#!/usr/bin/env bash
# Stops and removes the service from PM2. Linux/macOS.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$REPO_ROOT/.runtime/node/bin:$REPO_ROOT/.runtime/npm-global/bin:$PATH"

pm2 stop drive-auto-fetcher
pm2 delete drive-auto-fetcher
pm2 save

echo ""
echo "Stopped. PM2 will no longer run drive-auto-fetcher on startup."
echo "To fully remove the boot-time service entry, also run: pm2 unstartup"
