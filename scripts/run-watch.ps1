# Runs continuously in this terminal window (foreground), checking Drive on
# the interval set in config.json. Close the window to stop. Windows.
# For a background service that survives closing the terminal / reboots,
# use scripts\start-service.ps1 (PM2) instead.
$RepoRoot = Split-Path -Parent $PSScriptRoot
$pinned   = Join-Path $RepoRoot ".runtime\python_path.txt"
$Python   = if (Test-Path $pinned) { (Get-Content $pinned -Raw).Trim() } else { "python" }

Write-Host "============================================"
Write-Host " Drive Auto-Fetcher - Watch Mode (foreground)"
Write-Host " Close this window to stop."
Write-Host "============================================"
Write-Host ""
& $Python (Join-Path $RepoRoot "src\drive_fetcher.py") --watch
