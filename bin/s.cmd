@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0s.ps1' --% %*"
exit /b %ERRORLEVEL%
