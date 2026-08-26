@echo off
setlocal

powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%~dp0bootstrap.ps1"

set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
    echo Bootstrap failed.
) else (
    echo Bootstrap completed.
)

exit /b %EXITCODE%