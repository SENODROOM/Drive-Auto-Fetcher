# ============================================================
#  windows-task-scheduler-alternative.ps1
#  Alternative to PM2: run ONCE as Administrator to register
#  Drive Auto-Fetcher as a Task Scheduler job that starts on login.
#
#  Most users should prefer installer.ps1 (PM2-based, restarts on
#  crash, no admin required). Use this only if PM2/Node.js isn't an
#  option on this machine.
# ============================================================

param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$pinned     = Join-Path $RepoRoot ".runtime\python_path.txt"
$pythonPath = if (Test-Path $pinned) { (Get-Content $pinned -Raw).Trim() } else { (Get-Command python -ErrorAction Stop).Source }
$scriptPath = Join-Path $RepoRoot "src\drive_fetcher.py"
$taskName   = "DriveAutoFetcher"

if (-not (Test-Path $scriptPath)) {
    Write-Error "drive_fetcher.py not found at: $scriptPath"
    exit 1
}

if (-not (Test-Path (Join-Path $RepoRoot "config.json"))) {
    Write-Error "config.json not found. Run installer.ps1 (or 'python src\configure.py') first."
    exit 1
}

Write-Host "Registering Task Scheduler job: $taskName" -ForegroundColor Cyan
Write-Host "  Python : $pythonPath"
Write-Host "  Script : $scriptPath"

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "  Removed old task."
}

$action   = New-ScheduledTaskAction -Execute $pythonPath -Argument "`"$scriptPath`" --watch" -WorkingDirectory $RepoRoot
$trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 5) `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName   $taskName `
    -Action     $action `
    -Trigger    $trigger `
    -Settings   $settings `
    -RunLevel   Highest `
    -Description "Drive Auto-Fetcher: watches Google Drive and downloads files per config.json" | Out-Null

Write-Host ""
Write-Host "Done! Script runs automatically in watch mode on every Windows login." -ForegroundColor Green
Write-Host "   Config file : $RepoRoot\config.json"
Write-Host "   Log file    : $RepoRoot\drive_fetcher.log"
Write-Host ""
Write-Host "To remove auto-start later:" -ForegroundColor Yellow
Write-Host "   Unregister-ScheduledTask -TaskName 'DriveAutoFetcher' -Confirm:`$false"
