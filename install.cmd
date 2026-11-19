@echo off
setlocal
if exist "%~dp0install.ps1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex"
)
exit /b %ERRORLEVEL%
