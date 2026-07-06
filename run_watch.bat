@echo off
cd /d "%~dp0"
echo ============================================
echo  Drive Auto-Fetcher v3 - Watch Mode
echo  Checks every 60 seconds for new files.
echo  Close this window to stop.
echo ============================================
echo.
python drive_fetcher.py --watch
pause
