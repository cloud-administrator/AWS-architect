@echo off

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Install-CodexPolicy.ps1"

exit /b %ERRORLEVEL%
