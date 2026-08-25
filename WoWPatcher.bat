@echo off
REM ---------------------------------------------------------------
REM  WoW Patcher - keeps your client patch up to date, then launches
REM  the game. Put this file in your WoW folder, next to Wow.exe.
REM
REM  Run "WoWPatcher.bat keep" to hold the window open and read the
REM  output, even when nothing needed updating.
REM ---------------------------------------------------------------
setlocal
cd /d "%~dp0"

set KEEP=0
if /i "%~1"=="keep" set KEEP=1

if not exist "Wow.exe" (
  echo.
  echo   ERROR: Wow.exe was not found in this folder.
  echo   Put WoWPatcher.bat and patcher.ps1 in your WoW folder, next to Wow.exe.
  echo.
  pause
  exit /b 1
)

if not exist "patcher.ps1" (
  echo.
  echo   ERROR: patcher.ps1 is missing. It must sit next to this file.
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patcher.ps1"
set RC=%ERRORLEVEL%

REM 0 = already up to date, nothing to read, launch straight away
REM 10 = a patch was installed, hold it on screen briefly so it can be read
REM anything else = a real problem, stop and wait
if "%RC%"=="0"  goto launch
if "%RC%"=="10" goto updated

echo.
echo   The patcher reported a problem ^(code %RC%^). The game was not started.
echo.
pause
exit /b %RC%

:updated
echo.
echo   Update complete. Starting the game in a few seconds...
echo   ^(press a key to start now^)
timeout /t 8 >nul
goto launch

:launch
if "%KEEP%"=="1" (
  echo.
  pause
)
start "" "Wow.exe"
exit /b 0
