@echo off
rem Abre o instalador do ORION ServiceLog sem exigir mudanca na politica de
rem execucao do PowerShell. Aceita as mesmas opcoes do install-windows.ps1:
rem   -Desktop   -NoBuild   -Uninstall
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-windows.ps1" %*
set RESULTADO=%ERRORLEVEL%
echo.
pause
exit /b %RESULTADO%
