@echo off
cd /d "%~dp0\.."
echo ============================================
echo  Drive Auto-Fetcher - Watch Mode
echo  Checks periodically for new files (see config.json).
echo  Close this window to stop.
echo ============================================
echo.
python src\drive_fetcher.py --watch
pause
