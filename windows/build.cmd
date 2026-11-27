@echo off
rem Builds Folio Studio for Windows (FolioStudio-<version>-x64.msi on your Desktop).
rem Needs MSYS2 from https://www.msys2.org installed in C:\msys64 (or set MSYS2_ROOT).
setlocal
if "%MSYS2_ROOT%"=="" set "MSYS2_ROOT=C:\msys64"
if not exist "%MSYS2_ROOT%\usr\bin\bash.exe" (
  echo MSYS2 isn't installed in %MSYS2_ROOT%. Install it from https://www.msys2.org and run this again.
  pause
  exit /b 1
)
set "MSYSTEM=UCRT64"
set "CHERE_INVOKING=1"
rem MSYS2 updated first: a new MSYS2 has no package lists yet, and updating its own core ends the
rem shell it runs in, so it goes twice, each in a shell of its own
echo Updating MSYS2 (the first time takes a few minutes)...
"%MSYS2_ROOT%\usr\bin\bash.exe" -lc "pacman -Syu --noconfirm" > NUL 2>&1
"%MSYS2_ROOT%\usr\bin\bash.exe" -lc "pacman -Syu --noconfirm" > NUL 2>&1
"%MSYS2_ROOT%\usr\bin\bash.exe" -lc "bash \"$(cygpath -u '%~dp0')build.sh\""
echo.
pause
