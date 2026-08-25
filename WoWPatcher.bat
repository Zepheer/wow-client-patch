@echo off
REM ---------------------------------------------------------------
REM  WoW Patcher - keeps your client patch up to date, then launches
REM  the game. Put this file in your WoW folder, next to Wow.exe.
REM ---------------------------------------------------------------
setlocal
cd /d "%~dp0"

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

if not "%RC%"=="0" (
  echo.
  echo   The patcher reported a problem ^(code %RC%^). The game was not started.
  echo.
  pause
  exit /b %RC%
)

start "" "Wow.exe"
exit /b 0
