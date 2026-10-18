@echo off
rem ============================================================
rem  DeepSeek Harness - (re)create the Windows shortcuts.
rem    Every path is taken from the folder holding this file,
rem    so nothing is hardcoded and a moved checkout only needs
rem    this script run once more.
rem    With no arguments: this folder + desktop + Start Menu.
rem    With arguments: forwarded to install-shortcut.ps1, e.g.
rem      install-shortcut.cmd -Destination D:\links
rem      install-shortcut.cmd -Desktop
rem ============================================================
setlocal EnableExtensions
set "ARGS=%*"
if not defined ARGS set "ARGS=-Desktop -StartMenu"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-shortcut.ps1" %ARGS%
if errorlevel 1 (
    echo.
    echo [DeepSeek Harness] shortcut creation failed.
    pause
    exit /b 1
)
echo.
pause
