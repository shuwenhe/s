@echo off
setlocal
if exist "%~dp0s.exe" (
    set "PATH=C:\msys64\mingw64\bin;C:\msys64\usr\bin;%PATH%"
    "%~dp0s.exe" %*
    exit /b %ERRORLEVEL%
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0s.ps1' --% %*"
exit /b %ERRORLEVEL%
