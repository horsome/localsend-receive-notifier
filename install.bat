@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

echo.
echo  ==================================================
echo    LocalSend Receive Notifier - Setup
echo  ==================================================
echo.
echo   This will configure:
echo     1. Deploy scripts to %%LOCALAPPDATA%%\LocalSendToast
echo     2. Register protocol localsendfolder://
echo     3. Create logon task LocalSendToastMonitor
echo     4. Start the monitor now
echo.
echo   Watch folder is read automatically from LocalSend settings.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*

echo.
pause
