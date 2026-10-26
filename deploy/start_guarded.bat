@echo off
REM ============================================================
REM  Classroom AI Camera - guarded start (unattended)
REM  Double-click to run. Close this window to stop the service.
REM  All messages are ASCII on purpose: cmd.exe may not decode
REM  UTF-8 Chinese correctly depending on the system code page.
REM ============================================================
cd /d "%~dp0.."
set ROOT=%CD%

REM --- Optional security: uncomment and set a token so that only
REM --- clients carrying it can view the stream or delete files.
REM set CLASSROOM_API_TOKEN=replace-with-a-long-random-string

echo Starting classroom camera service (guarded)...
echo Project root: %ROOT%
echo Log file:     %ROOT%\work\watchdog.log
echo.

py -3.12 -u deploy\watchdog.py --source 0 --host 0.0.0.0 --behavior --behavior-model-dir "%ROOT%\models" --behavior-infer-fps 2 --camera-width 1280 --camera-height 720

echo.
echo Service stopped. Press any key to close.
pause >nul
