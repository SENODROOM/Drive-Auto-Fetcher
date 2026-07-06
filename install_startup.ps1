# ============================================================
#  install_startup.ps1
#  Run ONCE as Administrator to register auto-start on login
# ============================================================

param(
    [string]$ScriptDir = $PSScriptRoot
)

$pythonPath = (Get-Command python -ErrorAction Stop).Source
$scriptPath = Join-Path $ScriptDir "drive_fetcher.py"
$taskName   = "DriveAutoFetcher"

if (-not (Test-Path $scriptPath)) {
    Write-Error "drive_fetcher.py not found in: $ScriptDir"
    exit 1
}

Write-Host "Registering Task Scheduler job: $taskName" -ForegroundColor Cyan
Write-Host "  Python : $pythonPath"
Write-Host "  Script : $scriptPath"

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "  Removed old task."
}

$action   = New-ScheduledTaskAction -Execute $pythonPath -Argument "`"$scriptPath`"" -WorkingDirectory $ScriptDir
$trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
    -RestartCount 2 `
    -RestartInterval (New-TimeSpan -Minutes 5) `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName   $taskName `
    -Action     $action `
    -Trigger    $trigger `
    -Settings   $settings `
    -RunLevel   Highest `
    -Description "Auto-downloads Google Drive files to D:\Youtube on login" | Out-Null

Write-Host ""
Write-Host "✅ Done! Script runs automatically on every Windows login." -ForegroundColor Green
Write-Host "   Files saved to : D:\Youtube"
Write-Host "   Log file       : $ScriptDir\drive_fetcher.log"
Write-Host ""
Write-Host "To remove auto-start later:" -ForegroundColor Yellow
Write-Host "   Unregister-ScheduledTask -TaskName 'DriveAutoFetcher' -Confirm:`$false"
