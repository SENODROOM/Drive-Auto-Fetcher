@echo off
cd /d "%~dp0\.."
echo ============================================
echo  Drive Auto-Fetcher - Single Run
echo ============================================
echo Checking Google Drive for new files...
echo.
python src\drive_fetcher.py
echo.
echo Done! Check drive_fetcher.log for details.
pause
