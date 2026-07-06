@echo off
REM One-click production setup. Installs Python/Node/PM2 if missing,
REM installs dependencies, configures the app, logs in to Google,
REM and starts the background service.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
pause
