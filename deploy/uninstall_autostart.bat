@echo off
REM ============================================================
REM  Stop and remove the auto-start task.
REM ============================================================
schtasks /end /tn "ClassroomCamera" >nul 2>&1
schtasks /delete /tn "ClassroomCamera" /f

if errorlevel 1 (
  echo FAILED or task did not exist.
) else (
  echo Auto-start task removed.
)
echo.
pause
