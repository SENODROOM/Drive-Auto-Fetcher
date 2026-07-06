@echo off
cd /d "%~dp0"
echo ============================================
echo  Drive Auto-Fetcher v3 - Single Run
echo ============================================
echo Checking Google Drive for new files...
echo.
python drive_fetcher.py
echo.
echo Done! Check drive_fetcher.log for details.
pause
