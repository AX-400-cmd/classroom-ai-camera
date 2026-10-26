@echo off
REM ============================================================
REM  Register the service to start automatically at Windows logon.
REM  No administrator rights required for /sc onlogon.
REM ============================================================
schtasks /create /tn "ClassroomCamera" /tr "\"%~dp0start_guarded.bat\"" /sc onlogon /rl highest /f

if errorlevel 1 (
  echo.
  echo FAILED. Right-click this file and choose "Run as administrator".
) else (
  echo.
  echo Registered successfully. It will start at your next logon.
  echo.
  echo Start now :  schtasks /run /tn "ClassroomCamera"
  echo Stop      :  schtasks /end /tn "ClassroomCamera"
  echo Remove    :  schtasks /delete /tn "ClassroomCamera" /f
)
echo.
pause
