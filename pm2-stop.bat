@echo off
cd /d "%~dp0"

echo ============================================================
echo   Drive Auto-Fetcher — Stop / Uninstall
echo ============================================================
echo.
echo Stopping and removing from PM2...
pm2 stop drive-auto-fetcher
pm2 delete drive-auto-fetcher
pm2 save

echo.
echo ✅ Stopped. PM2 will no longer run drive-auto-fetcher on startup.
echo.
echo To completely remove PM2 auto-startup from Windows, run:
echo   pm2-startup uninstall
echo.
pause
