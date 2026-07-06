@echo off
cd /d "%~dp0"

echo ============================================================
echo   Drive Auto-Fetcher — First Time Setup
echo ============================================================
echo.
echo This will:
echo   1. Install Python dependencies
echo   2. Open your browser to log in to Google (one time only)
echo   3. Save your login token so PM2 never needs a browser again
echo.
echo Press any key to start...
pause >nul

echo.
echo [1/2] Installing Python dependencies...
pip install -r requirements.txt
if %errorlevel% neq 0 (
    echo.
    echo ERROR: pip failed. Make sure Python is installed and in PATH.
    echo Download Python from: https://www.python.org/downloads/
    pause
    exit /b 1
)

echo.
echo [2/2] Opening browser for Google login...
echo       Log in and click Allow. This only happens once.
echo.
python drive_fetcher.py
echo.
echo ============================================================
echo   Setup complete! token.json has been saved.
echo   Now run:  start_pm2.bat
echo ============================================================
pause
