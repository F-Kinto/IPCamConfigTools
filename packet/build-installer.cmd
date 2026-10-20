@echo off
rem Double-click entry to build the NSIS installer.
rem It runs build-installer.ps1 in the same folder, then pauses so the
rem result stays visible when launched by double-click.

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-installer.ps1"
set EXITCODE=%ERRORLEVEL%
echo.
if "%EXITCODE%"=="0" (
    echo ==== BUILD OK, installer is in packet\dist\
) else (
    echo ==== BUILD FAILED, exit code %EXITCODE%
)
pause
