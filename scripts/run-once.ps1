# Runs a single check-and-download pass, then exits. Windows.
$RepoRoot = Split-Path -Parent $PSScriptRoot
$pinned   = Join-Path $RepoRoot ".runtime\python_path.txt"
$Python   = if (Test-Path $pinned) { (Get-Content $pinned -Raw).Trim() } else { "python" }

Write-Host "============================================"
Write-Host " Drive Auto-Fetcher - Single Run"
Write-Host "============================================"
Write-Host "Checking Google Drive for new files..."
Write-Host ""
& $Python (Join-Path $RepoRoot "src\drive_fetcher.py")
Write-Host ""
Write-Host "Done! Check drive_fetcher.log for details."
