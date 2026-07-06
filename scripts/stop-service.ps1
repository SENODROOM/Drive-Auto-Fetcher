# Stops and removes the service from PM2. Windows.
pm2 stop drive-auto-fetcher
pm2 delete drive-auto-fetcher
pm2 save

Write-Host ""
Write-Host "Stopped. PM2 will no longer run drive-auto-fetcher on startup." -ForegroundColor Green
Write-Host "To fully remove PM2's Windows auto-start entry, also run: pm2-startup uninstall"
