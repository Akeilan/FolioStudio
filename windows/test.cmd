@echo off
rem Checks the installed Folio Studio: every app's own tests, run on this computer. Writes
rem folio-test-report.txt on your Desktop; send that file back.
setlocal
if "%MSYS2_ROOT%"=="" set "MSYS2_ROOT=C:\msys64"
set "FOLIO_ROOT=%ProgramFiles%\Folio Studio"
if not exist "%FOLIO_ROOT%\runtime\bin\python.exe" (
  echo Folio Studio isn't installed in %FOLIO_ROOT%. Install the MSI first.
  pause
  exit /b 1
)
"%FOLIO_ROOT%\runtime\bin\python.exe" "%~dp0test-windows.py" %*
echo.
pause
