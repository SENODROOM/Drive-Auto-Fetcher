# ============================================================
#  setup.ps1 — Drive Auto-Fetcher one-shot production setup
#
#  Designed for a completely bare Windows machine: if Python and/or
#  Node.js/PM2 are missing, this script installs them itself (via
#  winget), then installs the Python dependencies, walks you through
#  configuration, performs the one-time Google login, and starts the
#  service under PM2 so it survives reboots and crashes.
#
#  Safe to re-run: every step is skipped if already satisfied.
# ============================================================

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Test-CommandExists($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Update-SessionPath {
    # Installers (winget/npm) update the registry PATH but this process
    # doesn't see it until we reload it from both machine and user scope.
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Install-WithWinget($id, $friendlyName) {
    if (-not (Test-CommandExists "winget")) {
        Write-Host ""
        Write-Host "  winget is not available on this machine." -ForegroundColor Yellow
        Write-Host "  Install $friendlyName manually, then re-run this script:" -ForegroundColor Yellow
        Write-Host "    https://www.google.com/search?q=download+$friendlyName" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "  Installing $friendlyName via winget (id: $id)..."
    winget install -e --id $id --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install $friendlyName via winget."
        exit 1
    }
    Update-SessionPath
}

# ── 1. Python ────────────────────────────────────────────────────────────────
Write-Step "Checking for Python"
if (Test-CommandExists "python") {
    Write-Host "  Found: $(python --version)"
} else {
    Write-Host "  Python not found — installing it for you..."
    Install-WithWinget -id "Python.Python.3.12" -friendlyName "Python 3.12"
    if (-not (Test-CommandExists "python")) {
        Write-Host ""
        Write-Host "  Python was installed but isn't visible in this terminal yet." -ForegroundColor Yellow
        Write-Host "  Close this window, open a NEW terminal, and re-run scripts\setup.ps1." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "  Installed: $(python --version)"
}

# ── 2. Node.js + npm (required for PM2) ──────────────────────────────────────
Write-Step "Checking for Node.js"
if (Test-CommandExists "node") {
    Write-Host "  Found: $(node --version)"
} else {
    Write-Host "  Node.js not found — installing it for you..."
    Install-WithWinget -id "OpenJS.NodeJS.LTS" -friendlyName "Node.js LTS"
    if (-not (Test-CommandExists "node")) {
        Write-Host ""
        Write-Host "  Node.js was installed but isn't visible in this terminal yet." -ForegroundColor Yellow
        Write-Host "  Close this window, open a NEW terminal, and re-run scripts\setup.ps1." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "  Installed: $(node --version)"
}

# ── 3. Python dependencies ───────────────────────────────────────────────────
Write-Step "Installing Python dependencies"
python -m pip install --upgrade pip --quiet
python -m pip install -r (Join-Path $RepoRoot "requirements.txt")
if ($LASTEXITCODE -ne 0) {
    Write-Error "pip install failed. See output above."
    exit 1
}

# ── 4. PM2 ───────────────────────────────────────────────────────────────────
Write-Step "Checking for PM2"
if (Test-CommandExists "pm2") {
    Write-Host "  Found: pm2 $(pm2 --version)"
} else {
    Write-Host "  PM2 not found — installing it for you..."
    npm install -g pm2
    npm install -g pm2-windows-startup
    Update-SessionPath
    if (-not (Test-CommandExists "pm2")) {
        Write-Host ""
        Write-Host "  PM2 was installed but isn't visible in this terminal yet." -ForegroundColor Yellow
        Write-Host "  Close this window, open a NEW terminal, and re-run scripts\setup.ps1." -ForegroundColor Yellow
        exit 1
    }
}

# ── 5. Google OAuth credentials.json ─────────────────────────────────────────
Write-Step "Checking for credentials.json"
$credentialsPath = Join-Path $RepoRoot "credentials.json"
if (-not (Test-Path $credentialsPath)) {
    Write-Host ""
    Write-Host "  credentials.json is missing. This can't be created automatically —" -ForegroundColor Yellow
    Write-Host "  it comes from your own Google Cloud project. See README.md, section" -ForegroundColor Yellow
    Write-Host "  'Get Google API Credentials', then re-run scripts\setup.ps1." -ForegroundColor Yellow
    exit 1
}
Write-Host "  Found: $credentialsPath"

# ── 6. Configuration wizard ──────────────────────────────────────────────────
Write-Step "Configuration"
$configPath = Join-Path $RepoRoot "config.json"
if (Test-Path $configPath) {
    Write-Host "  config.json already exists. Skipping wizard (delete it, or run"
    Write-Host "  'python src\configure.py' directly, to change your settings)."
} else {
    python (Join-Path $RepoRoot "src\configure.py")
    if (-not (Test-Path $configPath)) {
        Write-Error "Configuration was not saved. Re-run scripts\setup.ps1 to try again."
        exit 1
    }
}

# ── 7. One-time Google login ─────────────────────────────────────────────────
Write-Step "Google account login"
$tokenPath = Join-Path $RepoRoot "token.json"
if (Test-Path $tokenPath) {
    Write-Host "  token.json already exists — skipping login."
} else {
    Write-Host "  Opening your browser to log in to Google (one time only)..."
    python (Join-Path $RepoRoot "src\drive_fetcher.py") --auth-only
    if (-not (Test-Path $tokenPath)) {
        Write-Error "Login did not complete. Re-run scripts\setup.ps1 to try again."
        exit 1
    }
}

# ── 8. Start under PM2 ───────────────────────────────────────────────────────
Write-Step "Starting the service with PM2"
Push-Location $RepoRoot
try {
    pm2 start ecosystem.config.js
    pm2 save
    pm2-startup install
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Setup complete! Drive Auto-Fetcher is running in the background." -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  pm2 list                        — check status"
Write-Host "  pm2 logs drive-auto-fetcher     — view live logs"
Write-Host "  pm2 restart drive-auto-fetcher  — apply changes to config.json"
Write-Host "  pm2 stop drive-auto-fetcher     — stop temporarily"
Write-Host ""
