# (Re)starts the background PM2 service and registers it to auto-start on
# Windows boot. Requires that installer.ps1 has already been run at least
# once (PM2 installed, config.json + token.json present). Windows.
$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command pm2 -ErrorAction SilentlyContinue)) {
    Write-Host "PM2 not found. Run installer.ps1 first." -ForegroundColor Yellow
    exit 1
}
if (-not (Test-Path (Join-Path $RepoRoot "config.json"))) {
    Write-Host "config.json not found. Run installer.ps1 first (or: python src\configure.py)." -ForegroundColor Yellow
    exit 1
}
if (-not (Test-Path (Join-Path $RepoRoot "token.json"))) {
    Write-Host "token.json not found. Run installer.ps1 first to log in to Google." -ForegroundColor Yellow
    exit 1
}

Push-Location $RepoRoot
try {
    pm2 start ecosystem.config.js
    pm2 save
    pm2-startup install
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Started. Useful commands:" -ForegroundColor Green
Write-Host "  pm2 list"
Write-Host "  pm2 logs drive-auto-fetcher"
Write-Host "  pm2 restart drive-auto-fetcher"
