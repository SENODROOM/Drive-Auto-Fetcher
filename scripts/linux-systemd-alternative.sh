#!/usr/bin/env bash
# ============================================================
#  linux-systemd-alternative.sh
#  Alternative to PM2: registers Drive Auto-Fetcher as a systemd --user
#  service that starts on boot/login and restarts on crash.
#
#  Most users should prefer installer.sh (PM2-based). Use this only if
#  you'd rather not have Node.js/PM2 installed at all on this machine —
#  it only needs Python.
# ============================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINNED="$REPO_ROOT/.runtime/python_path.txt"
PYTHON_BIN="$(command -v python3 || true)"
[ -f "$PINNED" ] && PYTHON_BIN="$(cat "$PINNED")"

if [ -z "$PYTHON_BIN" ]; then
    echo "No Python 3 found. Run ./installer.sh first, or install Python 3 manually." >&2
    exit 1
fi
if [ ! -f "$REPO_ROOT/config.json" ]; then
    echo "config.json not found. Run: python3 src/configure.py" >&2
    exit 1
fi

UNIT_DIR="$HOME/.config/systemd/user"
UNIT_FILE="$UNIT_DIR/drive-auto-fetcher.service"
mkdir -p "$UNIT_DIR"

cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Drive Auto-Fetcher (watches Google Drive, downloads per config.json)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$REPO_ROOT
ExecStart=$PYTHON_BIN $REPO_ROOT/src/drive_fetcher.py --watch
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now drive-auto-fetcher.service

# Let the user service keep running after logout / across boots without an
# active login session.
if command -v loginctl >/dev/null 2>&1; then
    loginctl enable-linger "$USER" 2>/dev/null || \
        echo "Note: could not enable lingering automatically — if the service" \
             "stops after you log out, run: sudo loginctl enable-linger $USER"
fi

echo ""
echo "Done! Registered as a systemd --user service: drive-auto-fetcher.service"
echo ""
echo "  systemctl --user status drive-auto-fetcher   — check status"
echo "  journalctl --user -u drive-auto-fetcher -f    — view live logs"
echo "  systemctl --user restart drive-auto-fetcher  — apply config.json changes"
echo "  systemctl --user disable --now drive-auto-fetcher  — remove"
