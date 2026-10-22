:: 正在生成中文翻译文件
echo.
echo [1/10] generating VmsTranslator_EN.qm lrelease...
lrelease ./VmsTsFile/VmsTranslator_EN.ts -qm ./en/VmsTranslator_EN.qm
if %ERRORLEVEL% neq 0 (
    echo.
    echo [Error] lrelease generate failed  Error code: %ERRORLEVEL%
    goto :error
)
echo [Success] lrelease finish
echo [Success] Generate Success VmsTranslator_en_EN.qm 
:: -------------------------------------------------------------------
:: Finish
:: -------------------------------------------------------------------

echo.
echo ===== Bat Finish =====
pause
exit /b 0

:error
echo.
echo =====  Error occurs =====
echo Error occurs at: %time%
pause
exit /b 1