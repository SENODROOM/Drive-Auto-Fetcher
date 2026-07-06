#!/usr/bin/env bash
# ============================================================
#  installer.sh — Drive Auto-Fetcher, Linux/macOS one-click setup
#
#  Works on a completely bare machine: if Python 3 and/or Node.js/PM2
#  aren't installed, this script installs them itself — first via the
#  system package manager (apt/dnf/yum/pacman/zypper/apk on Linux,
#  Homebrew on macOS), and if none of those are available, by
#  downloading self-contained, prebuilt binaries directly (no sudo,
#  no system-wide changes) into a ".runtime" folder inside this repo.
#
#  All Python dependencies are installed into a dedicated virtualenv
#  (.runtime/venv) rather than the system Python, so this never fights
#  with the OS's own package manager (relevant on modern Debian/Ubuntu,
#  which blocks "pip install" against the system Python by default).
#
#  Then it installs dependencies, walks you through configuration,
#  performs the one-time Google login, and starts the service under
#  PM2 so it survives reboots and crashes.
#
#  Safe to re-run: every step is skipped if already satisfied.
#
#  Usage:
#      chmod +x installer.sh && ./installer.sh
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$REPO_ROOT/.runtime"
OS_NAME="$(uname -s)"          # Linux | Darwin
ARCH_NAME="$(uname -m)"        # x86_64 | aarch64 | arm64

PBS_RELEASE_TAG="20240814"     # python-build-standalone release used for the no-package-manager fallback
PBS_PY_VERSION="3.12.5"
NODE_VERSION="20.16.0"

step()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
warn()  { printf '\033[1;33m%s\033[0m\n' "$1"; }
has()   { command -v "$1" >/dev/null 2>&1; }

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif has sudo; then
        sudo "$@"
    else
        warn "  Need root to run: $* — and 'sudo' isn't available. Skipping."
        return 1
    fi
}

# ── Package manager detection (Linux only; macOS uses Homebrew) ─────────────
detect_pkg_manager() {
    if has apt-get; then echo "apt"; return; fi
    if has dnf;     then echo "dnf"; return; fi
    if has yum;     then echo "yum"; return; fi
    if has pacman;  then echo "pacman"; return; fi
    if has zypper;  then echo "zypper"; return; fi
    if has apk;     then echo "apk"; return; fi
    echo "none"
}

install_via_pkg_manager() {
    # $1 = "python" or "node"
    local pm; pm="$(detect_pkg_manager)"
    case "$pm-$1" in
        apt-python)    as_root apt-get update -y && as_root apt-get install -y python3 python3-venv python3-pip ;;
        apt-node)      as_root apt-get update -y && as_root apt-get install -y nodejs npm ;;
        dnf-python)    as_root dnf install -y python3 python3-pip ;;
        dnf-node)      as_root dnf install -y nodejs npm ;;
        yum-python)    as_root yum install -y python3 python3-pip ;;
        yum-node)      as_root yum install -y nodejs npm ;;
        pacman-python) as_root pacman -Sy --noconfirm python python-pip ;;
        pacman-node)   as_root pacman -Sy --noconfirm nodejs npm ;;
        zypper-python) as_root zypper install -y python3 python3-pip ;;
        zypper-node)   as_root zypper install -y nodejs npm ;;
        apk-python)    as_root apk add --no-cache python3 py3-pip ;;
        apk-node)      as_root apk add --no-cache nodejs npm ;;
        *) return 1 ;;
    esac
}

# ── Python: PATH -> brew (macOS) / package manager (Linux) -> standalone download ──
resolve_python_seed() {
    if has python3; then
        echo "python3"
        return
    fi

    if [ "$OS_NAME" = "Darwin" ] && has brew; then
        step "Installing Python via Homebrew" >&2
        brew install python
        if has python3; then echo "python3"; return; fi
    elif [ "$OS_NAME" = "Linux" ]; then
        step "Installing Python via system package manager" >&2
        if install_via_pkg_manager python && has python3; then
            echo "python3"
            return
        fi
    fi

    # Fallback: self-contained standalone build, no sudo, no package manager.
    step "Downloading a self-contained Python (no package manager available)" >&2
    local tag arch_tag os_tag url tarball extract_dir
    case "$ARCH_NAME" in
        x86_64) arch_tag="x86_64" ;;
        aarch64|arm64) arch_tag="aarch64" ;;
        *) echo "Unsupported architecture: $ARCH_NAME. Install Python 3 manually and re-run." >&2; exit 1 ;;
    esac
    if [ "$OS_NAME" = "Darwin" ]; then
        os_tag="apple-darwin"
    else
        os_tag="unknown-linux-gnu"
    fi
    tarball="cpython-${PBS_PY_VERSION}+${PBS_RELEASE_TAG}-${arch_tag}-${os_tag}-install_only.tar.gz"
    url="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_RELEASE_TAG}/${tarball}"

    mkdir -p "$RUNTIME_DIR"
    extract_dir="$RUNTIME_DIR/_python_extract"
    mkdir -p "$extract_dir"
    echo "  Downloading: $url" >&2
    curl -fL --progress-bar -o "$RUNTIME_DIR/$tarball" "$url"
    tar -xzf "$RUNTIME_DIR/$tarball" -C "$extract_dir"
    rm -f "$RUNTIME_DIR/$tarball"
    rm -rf "$RUNTIME_DIR/python"
    mv "$extract_dir/python" "$RUNTIME_DIR/python"
    rm -rf "$extract_dir"

    if [ ! -x "$RUNTIME_DIR/python/bin/python3" ]; then
        echo "Standalone Python download/extract failed. Install Python 3 manually and re-run installer.sh." >&2
        exit 1
    fi
    echo "$RUNTIME_DIR/python/bin/python3"
}

# ── Node.js: PATH -> brew (macOS) / package manager (Linux) -> prebuilt tarball ──
resolve_node() {
    if has node && has npm; then
        echo "  Found on PATH: node $(node --version)"
        return
    fi

    if [ -x "$RUNTIME_DIR/node/bin/node" ]; then
        echo "  Found previously downloaded copy: $RUNTIME_DIR/node"
        export PATH="$RUNTIME_DIR/node/bin:$PATH"
        persist_path_entry "$RUNTIME_DIR/node/bin"
        return
    fi

    if [ "$OS_NAME" = "Darwin" ] && has brew; then
        echo "  Installing Node.js via Homebrew..."
        brew install node
        if has node && has npm; then return; fi
    elif [ "$OS_NAME" = "Linux" ]; then
        echo "  Installing Node.js via system package manager..."
        if install_via_pkg_manager node && has node && has npm; then
            return
        fi
    fi

    echo "  Downloading a self-contained Node.js (no package manager available)..."
    local arch_tag os_tag dist_name url
    case "$ARCH_NAME" in
        x86_64) arch_tag="x64" ;;
        aarch64|arm64) arch_tag="arm64" ;;
        *) echo "Unsupported architecture: $ARCH_NAME. Install Node.js manually and re-run." >&2; exit 1 ;;
    esac
    os_tag=$([ "$OS_NAME" = "Darwin" ] && echo "darwin" || echo "linux")
    dist_name="node-v${NODE_VERSION}-${os_tag}-${arch_tag}"
    url="https://nodejs.org/dist/v${NODE_VERSION}/${dist_name}.tar.xz"

    mkdir -p "$RUNTIME_DIR"
    echo "  Downloading: $url"
    curl -fL --progress-bar -o "$RUNTIME_DIR/$dist_name.tar.xz" "$url"
    tar -xJf "$RUNTIME_DIR/$dist_name.tar.xz" -C "$RUNTIME_DIR"
    rm -f "$RUNTIME_DIR/$dist_name.tar.xz"
    rm -rf "$RUNTIME_DIR/node"
    mv "$RUNTIME_DIR/$dist_name" "$RUNTIME_DIR/node"

    if [ ! -x "$RUNTIME_DIR/node/bin/node" ]; then
        echo "Node.js download/extract failed. Install Node.js manually from https://nodejs.org/ and re-run." >&2
        exit 1
    fi
    export PATH="$RUNTIME_DIR/node/bin:$PATH"
    persist_path_entry "$RUNTIME_DIR/node/bin"
    echo "  Installed self-contained Node.js: $RUNTIME_DIR/node"
}

persist_path_entry() {
    # Add $1 to PATH for future shells (idempotent) via ~/.profile.
    local dir="$1" rc="$HOME/.profile"
    local line="export PATH=\"$dir:\$PATH\""
    touch "$rc"
    if ! grep -qF "$dir" "$rc" 2>/dev/null; then
        printf '\n# Added by Drive Auto-Fetcher installer.sh\n%s\n' "$line" >> "$rc"
        warn "  Added $dir to PATH in $rc — run 'source $rc' or open a new terminal to use it directly."
    fi
}

# ============================================================
step "Checking for Python 3"
PYTHON_SEED="$(resolve_python_seed)"
echo "  Using: $PYTHON_SEED ($($PYTHON_SEED --version 2>&1))"

step "Checking for Node.js and npm"
resolve_node

step "Creating an isolated Python virtual environment (.runtime/venv)"
if [ ! -x "$RUNTIME_DIR/venv/bin/python3" ]; then
    if ! "$PYTHON_SEED" -m venv "$RUNTIME_DIR/venv" 2>/dev/null; then
        warn "  'venv' module missing — attempting to install it via the package manager..."
        if [ "$OS_NAME" = "Linux" ]; then
            pm="$(detect_pkg_manager)"
            [ "$pm" = "apt" ] && as_root apt-get install -y python3-venv || true
        fi
        "$PYTHON_SEED" -m venv "$RUNTIME_DIR/venv"
    fi
fi
PYTHON_BIN="$RUNTIME_DIR/venv/bin/python3"
mkdir -p "$RUNTIME_DIR"
echo "$PYTHON_BIN" > "$RUNTIME_DIR/python_path.txt"
echo "  Virtualenv ready: $PYTHON_BIN"

step "Installing Python dependencies"
"$PYTHON_BIN" -m pip install --upgrade pip --quiet
"$PYTHON_BIN" -m pip install -r "$REPO_ROOT/requirements.txt"

step "Checking for PM2"
if has pm2; then
    echo "  Found: pm2 $(pm2 --version)"
else
    echo "  PM2 not found — installing it (into a user-owned npm prefix, no sudo needed)..."
    mkdir -p "$RUNTIME_DIR/npm-global"
    npm config set prefix "$RUNTIME_DIR/npm-global"
    export PATH="$RUNTIME_DIR/npm-global/bin:$PATH"
    persist_path_entry "$RUNTIME_DIR/npm-global/bin"
    npm install -g pm2
    if ! has pm2; then
        echo "PM2 install failed. See output above." >&2
        exit 1
    fi
fi

step "Checking for credentials.json"
CREDENTIALS_PATH="$REPO_ROOT/credentials.json"
if [ ! -f "$CREDENTIALS_PATH" ]; then
    warn "  credentials.json is missing. This can't be created automatically —"
    warn "  it comes from your own Google Cloud project. See README.md, section"
    warn "  'Get Google API Credentials', then re-run ./installer.sh."
    exit 1
fi
echo "  Found: $CREDENTIALS_PATH"

step "Configuration"
CONFIG_PATH="$REPO_ROOT/config.json"
if [ -f "$CONFIG_PATH" ]; then
    echo "  config.json already exists. Skipping wizard (delete it, or run"
    echo "  '$PYTHON_BIN src/configure.py' directly, to change your settings)."
else
    "$PYTHON_BIN" "$REPO_ROOT/src/configure.py"
    if [ ! -f "$CONFIG_PATH" ]; then
        echo "Configuration was not saved. Re-run ./installer.sh to try again." >&2
        exit 1
    fi
fi

step "Google account login"
TOKEN_PATH="$REPO_ROOT/token.json"
if [ -f "$TOKEN_PATH" ]; then
    echo "  token.json already exists — skipping login."
else
    if [ -z "${DISPLAY:-}" ] && [ "$OS_NAME" = "Linux" ]; then
        warn "  No graphical display detected on this machine (headless server?)."
        warn "  The login step opens a browser — if none is available here, run"
        warn "  this same step on a desktop machine, then copy token.json over."
    fi
    echo "  Opening your browser to log in to Google (one time only)..."
    "$PYTHON_BIN" "$REPO_ROOT/src/drive_fetcher.py" --auth-only
    if [ ! -f "$TOKEN_PATH" ]; then
        echo "Login did not complete. Re-run ./installer.sh to try again." >&2
        exit 1
    fi
fi

step "Starting the service with PM2"
cd "$REPO_ROOT"
pm2 start ecosystem.config.js
pm2 save

STARTUP_CMD="$(pm2 startup 2>/dev/null | grep -E '^(sudo|env) ' || true)"
if [ -n "$STARTUP_CMD" ]; then
    echo "  Registering PM2 to start on boot..."
    eval "$STARTUP_CMD" || warn "  Could not auto-register startup. Run the command PM2 printed above manually."
else
    warn "  Could not determine the PM2 startup command automatically. Run 'pm2 startup' and follow its instructions to enable auto-start on boot."
fi

echo ""
printf '\033[1;32m============================================================\033[0m\n'
printf '\033[1;32m  Setup complete! Drive Auto-Fetcher is running in the background.\033[0m\n'
printf '\033[1;32m============================================================\033[0m\n'
echo ""
echo "  pm2 list                        — check status"
echo "  pm2 logs drive-auto-fetcher     — view live logs"
echo "  pm2 restart drive-auto-fetcher  — apply changes to config.json"
echo "  pm2 stop drive-auto-fetcher     — stop temporarily"
echo ""
