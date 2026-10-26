@echo off
setlocal

rem Map the project to a plain-ASCII virtual drive first.
rem See build_android.bat for the reason: the Dart AOT toolchain
rem cannot handle non-ASCII paths on Windows.
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

subst X: /d >nul 2>&1
subst X: "%ROOT%"
if errorlevel 1 (
  echo === ERROR: cannot map virtual drive X: ===
  goto :end
)
if not exist "X:\flutter_app\pubspec.yaml" (
  echo === ERROR: X:\flutter_app\pubspec.yaml not found ===
  subst X: /d >nul 2>&1
  goto :end
)

set "ADB=D:\Android\platform-tools\adb.exe"
set "JAVA_HOME=D:\Android\Android Studio\jbr"
set "ANDROID_HOME=D:\Android"
set "ANDROID_SDK_ROOT=D:\Android"
set "PATH=%JAVA_HOME%\bin;D:\Android\platform-tools;%PATH%"
set "FLUTTER=D:\Flutter\flutter\bin\flutter.bat"

cd /d "X:\flutter_app"

echo.
echo === Connected devices ===
"%ADB%" devices
echo.

set DEVICE=
for /f "tokens=1" %%d in ('"%ADB%" devices ^| findstr /r "device$"') do set DEVICE=%%d

if "%DEVICE%"=="" (
  echo No phone detected. Check:
  echo   1) Developer options + USB debugging enabled on the phone
  echo   2) Cable connected, and "Allow USB debugging" accepted
  echo   3) For Wi-Fi debugging run: adb connect PHONE_IP:5555
  goto :end
)

echo === Installing to %DEVICE% ===
call "%FLUTTER%" --no-version-check --suppress-analytics install
set RC=%ERRORLEVEL%
echo.
if "%RC%"=="0" (echo Installed. Open the app on your phone.) else (echo Install failed, exit code %RC%)

:end
echo.
pause
