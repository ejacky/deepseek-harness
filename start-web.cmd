@echo off
rem ============================================================
rem  DeepSeek Harness - single-icon toggle launcher.
rem    Click when NOT running -> start (harness opens the browser).
rem    Click when already running -> confirm-stop dialog.
rem ============================================================
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT=%~dp0"
cd /d "%ROOT%"

set "PORT=3080"

rem Locate the PID listening on PORT (literal anchor, first hit).
set "PID="
for /f "tokens=5" %%A in ('netstat -ano ^| findstr /c:":%PORT% " ^| findstr /c:"LISTENING"') do (
    if not defined PID set "PID=%%A"
)

if not defined PID goto start

rem ==== Already running: ask whether to stop (native VBScript MsgBox) ====
cscript //nologo "%ROOT%confirm-stop.vbs"
if "%ERRORLEVEL%"=="0" (
    echo [DeepSeek Harness] stopping PID %PID% ...
    taskkill /pid %PID% /t /f >nul 2>&1
    goto eof
)
rem Cancelled stop: do nothing.
goto eof

:start
echo [DeepSeek Harness] starting ...
pnpm dsh web

:eof
