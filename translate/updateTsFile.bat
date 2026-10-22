@echo off
SETLOCAL EnableExtensions
title Generate TS file
color 0A
echo.
echo ===== Start Execute =====

echo.
echo [1/3] Execute.. Convert_To_Gbk.ps1...
powershell -ExecutionPolicy Bypass -File Convert_To_Gbk.ps1
if %ERRORLEVEL% neq 0 echo [Error] Convert_To_Gbk.ps1 Execute failed! ErrorCode: %ERRORLEVEL% && goto :error
echo [Success] Convert_To_Gbk.ps1 Execute finish.

echo.
echo [Waiting] Pause 1s...
timeout /t 1 /nobreak >nul

echo.
echo [2/3] Executing... lupdate...
lupdate VmsTranslate.pro
if %ERRORLEVEL% neq 0 echo [Error] lupdate Execute failed! ErrorCode: %ERRORLEVEL% && goto :error
echo [Success] lupdate Execute success

echo.
echo [Waiting] Pause 1s...
timeout /t 1 /nobreak >nul

echo.
echo [3/3] Executing Gbk_convert_Utf8Bom.ps1...
powershell -ExecutionPolicy Bypass -File Gbk_convert_Utf8Bom.ps1
if %ERRORLEVEL% neq 0 echo [Error] Gbk_convert_Utf8Bom.ps1 Execute failed! ErrorCode: %ERRORLEVEL% && goto :error
echo [Success] Gbk_convert_Utf8Bom.ps1 Execute success

echo.
echo ===== Bat Finish =====
pause
exit /b 0

:error
echo.
echo ===== Error occurs =====
echo Error Occurs: %time%
pause
exit /b 1
