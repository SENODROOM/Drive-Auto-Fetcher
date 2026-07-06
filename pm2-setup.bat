@echo off
cd /d "%~dp0"

echo ============================================================
echo   Drive Auto-Fetcher — Starting with PM2
echo ============================================================
echo.

REM Check if PM2 is installed
pm2 --version >nul 2>&1
if %errorlevel% neq 0 (
    echo PM2 not found. Installing PM2...
    npm install -g pm2
    npm install -g pm2-windows-startup
    if %errorlevel% neq 0 (
        echo.
        echo ERROR: npm failed. Make sure Node.js is installed.
        echo Download from: https://nodejs.org/
        pause
        exit /b 1
    )
)

REM Check token.json exists
if not exist "token.json" (
    echo.
    echo ERROR: token.json not found!
    echo Run 1_first_time_setup.bat first to log in to Google.
    pause
    exit /b 1
)

echo Starting drive-auto-fetcher with PM2...
pm2 start ecosystem.config.js

echo.
echo Saving PM2 process list so it survives reboots...
pm2 save

echo.
echo Setting up PM2 to auto-start on Windows boot...
pm2-startup install

echo.
echo ============================================================
echo   ✅ Done! Drive Auto-Fetcher is now running in background.
echo.
echo   Useful commands:
echo     pm2 list                    — see if it's running
echo     pm2 logs drive-auto-fetcher — see live logs
echo     pm2 stop drive-auto-fetcher — stop it
echo     pm2 restart drive-auto-fetcher — restart it
echo ============================================================
pause
