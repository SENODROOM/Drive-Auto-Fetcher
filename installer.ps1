# ============================================================
#  installer.ps1 - Drive Auto-Fetcher, Windows one-click setup
#
#  Works on a completely bare machine: if Python and/or Node.js/PM2
#  aren't installed, this script installs them itself - first via
#  winget, and if winget isn't available (or fails), by downloading
#  the official installers directly from python.org / nodejs.org into
#  a self-contained ".runtime" folder inside this repo (no admin
#  rights required for that fallback path).
#
#  Then it installs the Python dependencies, walks you through
#  configuration, performs the one-time Google login, and starts the
#  service under PM2 so it survives reboots and crashes.
#
#  Safe to re-run: every step is skipped if already satisfied.
#
#  Usage (from a normal PowerShell prompt):
#      .\installer.ps1
#  Or, if double-clicking opens it in an editor instead of running it:
#      powershell -ExecutionPolicy Bypass -File installer.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$RepoRoot   = $PSScriptRoot
$RuntimeDir = Join-Path $RepoRoot ".runtime"

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

function Add-PersistentUserPath($dir) {
    $current = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($current -notlike "*$dir*") {
        [System.Environment]::SetEnvironmentVariable("Path", "$current;$dir", "User")
    }
    $env:Path = "$env:Path;$dir"
}

function Get-WindowsArch {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { return "arm64" }
    return "amd64"
}

# -- Python: PATH -> winget -> direct download into .runtime\python ----------
function Resolve-Python {
    if (Test-CommandExists "python") {
        Write-Host "  Found on PATH: $(python --version)"
        return "python"
    }

    $pinned = Join-Path $RuntimeDir "python\python.exe"
    if (Test-Path $pinned) {
        Write-Host "  Found previously downloaded copy: $pinned"
        return $pinned
    }

    if (Test-CommandExists "winget") {
        Write-Host "  Not found - installing Python via winget..."
        winget install -e --id Python.Python.3.12 --source winget --accept-package-agreements --accept-source-agreements
        Update-SessionPath
        if (Test-CommandExists "python") {
            Write-Host "  Installed: $(python --version)"
            return "python"
        }
        Write-Host "  winget install finished but 'python' isn't on PATH in this window yet." -ForegroundColor Yellow
        Write-Host "  Falling back to a direct, self-contained download instead..." -ForegroundColor Yellow
    } else {
        Write-Host "  winget isn't available on this machine - using a direct download instead."
    }

    # Direct-download fallback: installs into $RuntimeDir\python only, no admin
    # rights and no changes to the system/global PATH.
    $version = "3.12.5"
    $arch    = Get-WindowsArch
    $url     = "https://www.python.org/ftp/python/$version/python-$version-$arch.exe"
    $installerPath = Join-Path $env:TEMP "python-$version-$arch.exe"
    $targetDir     = Join-Path $RuntimeDir "python"

    Write-Host "  Downloading Python $version from python.org..."
    Invoke-WebRequest -Uri $url -OutFile $installerPath

    Write-Host "  Installing to $targetDir (per-user, no admin required)..."
    New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
    Start-Process -FilePath $installerPath -ArgumentList @(
        "/quiet", "InstallAllUsers=0", "PrependPath=0", "Include_launcher=0",
        "Include_test=0", "TargetDir=$targetDir"
    ) -Wait
    Remove-Item $installerPath -ErrorAction SilentlyContinue

    $pythonExe = Join-Path $targetDir "python.exe"
    if (-not (Test-Path $pythonExe)) {
        Write-Error "Python download/install failed. Install Python manually from https://www.python.org/downloads/ and re-run installer.ps1."
        exit 1
    }
    Write-Host "  Installed self-contained Python: $pythonExe"
    return $pythonExe
}

# -- Node.js: PATH -> winget -> direct download into .runtime\node -----------
function Resolve-NodeAndNpm {
    if ((Test-CommandExists "node") -and (Test-CommandExists "npm")) {
        Write-Host "  Found on PATH: node $(node --version)"
        return
    }

    $pinnedNode = Join-Path $RuntimeDir "node\node.exe"
    if (Test-Path $pinnedNode) {
        Write-Host "  Found previously downloaded copy: $pinnedNode"
        Add-PersistentUserPath (Join-Path $RuntimeDir "node")
        return
    }

    if (Test-CommandExists "winget") {
        Write-Host "  Not found - installing Node.js via winget..."
        winget install -e --id OpenJS.NodeJS.LTS --source winget --accept-package-agreements --accept-source-agreements
        Update-SessionPath
        if ((Test-CommandExists "node") -and (Test-CommandExists "npm")) {
            Write-Host "  Installed: node $(node --version)"
            return
        }
        Write-Host "  winget install finished but node/npm aren't on PATH in this window yet." -ForegroundColor Yellow
        Write-Host "  Falling back to a direct, self-contained download instead..." -ForegroundColor Yellow
    } else {
        Write-Host "  winget isn't available on this machine - using a direct download instead."
    }

    # Direct-download fallback: a portable, no-install .zip distribution.
    $version = "20.16.0"
    $arch    = if ((Get-WindowsArch) -eq "arm64") { "arm64" } else { "x64" }
    $zipName = "node-v$version-win-$arch"
    $url     = "https://nodejs.org/dist/v$version/$zipName.zip"
    $zipPath = Join-Path $env:TEMP "$zipName.zip"
    $extractRoot = Join-Path $RuntimeDir "_node_extract"
    $targetDir   = Join-Path $RuntimeDir "node"

    Write-Host "  Downloading Node.js v$version from nodejs.org..."
    Invoke-WebRequest -Uri $url -OutFile $zipPath

    Write-Host "  Extracting to $targetDir (no admin required)..."
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force
    if (Test-Path $targetDir) { Remove-Item $targetDir -Recurse -Force }
    Move-Item (Join-Path $extractRoot $zipName) $targetDir
    Remove-Item $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $zipPath -ErrorAction SilentlyContinue

    if (-not (Test-Path (Join-Path $targetDir "node.exe"))) {
        Write-Error "Node.js download/install failed. Install it manually from https://nodejs.org/ and re-run installer.ps1."
        exit 1
    }
    Add-PersistentUserPath $targetDir
    Write-Host "  Installed self-contained Node.js: $targetDir (added to your user PATH)"
}

# ============================================================
Write-Step "Checking for Python"
$PythonExe = Resolve-Python
if ($PythonExe -ne "python") {
    New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
    Set-Content -Path (Join-Path $RuntimeDir "python_path.txt") -Value $PythonExe -NoNewline
}

Write-Step "Checking for Node.js and npm"
Resolve-NodeAndNpm

Write-Step "Installing Python dependencies"
& $PythonExe -m pip install --upgrade pip --quiet
& $PythonExe -m pip install -r (Join-Path $RepoRoot "requirements.txt")
if ($LASTEXITCODE -ne 0) {
    Write-Error "pip install failed. See output above."
    exit 1
}

Write-Step "Checking for PM2"
if (Test-CommandExists "pm2") {
    Write-Host "  Found: pm2 $(pm2 --version)"
} else {
    Write-Host "  PM2 not found - installing it..."
    npm install -g pm2
    npm install -g pm2-windows-startup
    Update-SessionPath
    if (-not (Test-CommandExists "pm2")) {
        Write-Host ""
        Write-Host "  PM2 was installed but isn't visible in this terminal yet." -ForegroundColor Yellow
        Write-Host "  Close this window, open a NEW terminal, and re-run installer.ps1." -ForegroundColor Yellow
        exit 1
    }
}

Write-Step "Checking for credentials.json"
$credentialsPath = Join-Path $RepoRoot "credentials.json"
if (-not (Test-Path $credentialsPath)) {
    Write-Host ""
    Write-Host "  credentials.json is missing. This can't be created automatically -" -ForegroundColor Yellow
    Write-Host "  it comes from your own Google Cloud project. See README.md, section" -ForegroundColor Yellow
    Write-Host "  'Get Google API Credentials', then re-run installer.ps1." -ForegroundColor Yellow
    exit 1
}
Write-Host "  Found: $credentialsPath"

Write-Step "Configuration"
$configPath = Join-Path $RepoRoot "config.json"
if (Test-Path $configPath) {
    Write-Host "  config.json already exists. Skipping wizard (delete it, or run"
    Write-Host "  '$PythonExe src\configure.py' directly, to change your settings)."
} else {
    & $PythonExe (Join-Path $RepoRoot "src\configure.py")
    if (-not (Test-Path $configPath)) {
        Write-Error "Configuration was not saved. Re-run installer.ps1 to try again."
        exit 1
    }
}

Write-Step "Google account login"
$tokenPath = Join-Path $RepoRoot "token.json"
if (Test-Path $tokenPath) {
    Write-Host "  token.json already exists - skipping login."
} else {
    Write-Host "  Opening your browser to log in to Google (one time only)..."
    & $PythonExe (Join-Path $RepoRoot "src\drive_fetcher.py") --auth-only
    if (-not (Test-Path $tokenPath)) {
        Write-Error "Login did not complete. Re-run installer.ps1 to try again."
        exit 1
    }
}

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
Write-Host "  pm2 list                        - check status"
Write-Host "  pm2 logs drive-auto-fetcher     - view live logs"
Write-Host "  pm2 restart drive-auto-fetcher  - apply changes to config.json"
Write-Host "  pm2 stop drive-auto-fetcher     - stop temporarily"
Write-Host ""
