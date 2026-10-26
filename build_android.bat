@echo off
setlocal

rem ============================================================
rem  One-click release APK build.
rem
rem  WHY subst: the project sits under a non-ASCII path. AGP's
rem  check is bypassed (android.overridePathCheck=true), but the
rem  Dart AOT snapshotter (gen_snapshot.exe) still cannot open
rem  kernel files through a non-ASCII path and fails with:
rem      Error: Unable to read file ... app.dill
rem      Dart snapshot generator failed with exit code 255
rem  Fix: map the project root to a plain-ASCII drive letter X:
rem  and build from there. Files stay in their original place.
rem  The X: mapping disappears after a reboot; this script
rem  re-creates it on every run.
rem ============================================================

rem Project root = the folder that contains this script
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

rem Drop any previous X: mapping (ignore errors), then re-map
subst X: /d >nul 2>&1
subst X: "%ROOT%"
if errorlevel 1 (
  echo === ERROR: cannot map virtual drive X: ===
  echo The letter X: may be in use by another disk. Free it and retry.
  goto :end
)

if not exist "X:\flutter_app\pubspec.yaml" (
  echo === ERROR: X:\flutter_app\pubspec.yaml not found ===
  subst X: /d >nul 2>&1
  goto :end
)

set "JAVA_HOME=D:\Android\Android Studio\jbr"
set "ANDROID_HOME=D:\Android"
set "ANDROID_SDK_ROOT=D:\Android"
set "PATH=%JAVA_HOME%\bin;D:\Android\platform-tools;%PATH%"
set "FLUTTER=D:\Flutter\flutter\bin\flutter.bat"
set "OUTDIR=build\app\outputs\flutter-apk"

cd /d "X:\flutter_app"

echo.
echo === Step 1/2  pub get ===
call "%FLUTTER%" --no-version-check --suppress-analytics pub get
if errorlevel 1 goto :fail

echo.
echo === Step 2/2  build release APK (split-per-abi) ===
call "%FLUTTER%" --no-version-check --suppress-analytics build apk --release --split-per-abi
set RC=%ERRORLEVEL%

echo.
if not "%RC%"=="0" goto :fail

echo === BUILD OK ===
for %%f in ("X:\flutter_app\%OUTDIR%\*.apk") do echo   %%~nxf   %%~zf bytes
echo.
echo Full path (virtual drive):
echo   X:\flutter_app\%OUTDIR%\
echo Same files, physical location:
echo   %ROOT%\flutter_app\%OUTDIR%\
echo.
echo Most phones need: app-arm64-v8a-release.apk
echo To install on a connected phone, run install_android.bat
goto :end

:fail
echo === BUILD FAILED ===
echo Please copy the error output above.
echo Common causes:
echo   1) Android SDK missing  -  check that D:\Android exists
echo   2) JDK incompatible with Gradle  -  using D:\Android\Android Studio\jbr
echo   3) First build needs network access

:end
echo.
pause
