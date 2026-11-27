# Folio Studio for Windows

All seven apps (Page, Sheet, Show, Draw, Gable, Chord and Reel) in one MSI for Windows 10 and 11
(64-bit). The apps are the same code as on Linux. They run on a runtime the MSI installs with
them: Python, GTK, GStreamer, Qt and ffmpeg, taken from MSYS2's packages.

## Building the MSI

1. Install MSYS2 from https://www.msys2.org. Keep the usual folder, `C:\msys64`.
2. Double-click `windows\build.cmd` in this checkout of Folio Studio.

The script fetches the build tools and the runtime, then the apps' code from GitHub, and builds
them. The first run downloads a few gigabytes; later runs reuse them. When it finishes,
`FolioStudio-<version>-x64.msi` is on your Desktop. If something goes wrong, it says what and
names the log.

## Installing

Double-click the MSI. Folio Studio goes into `C:\Program Files\Folio Studio`, with a Start menu
folder of the seven apps.

- **File types:** each app is listed under "Open with" for the files it opens. It becomes the
  default only for its own formats (`.gbl` for Gable, `.reel` for Reel). Settings > Apps > Default
  apps can make it the default for the rest.
- **Updating:** a newer MSI replaces the older one in place.
- **Removing:** Settings > Apps removes it.

## Checking it

With Folio Studio installed, double-click `windows\test.cmd`. It runs every app's own tests on
the installed apps. This takes an hour or two, with windows opening and closing by themselves, so
leave the mouse and keyboard alone while it runs. `test.cmd --quick` runs a short version in a
few minutes.

The results are written to `folio-test-report.txt` on your Desktop. Send that file back.

## What differs from Linux

| Area | On Windows |
|---|---|
| Printing | Page prints through Windows' own printing. Draw hands the PDF to the default PDF program. |
| Mail | "Send as attachment" and mail merge use the default mail program (Simple MAPI: Outlook, Thunderbird and others). |
| Light or dark | Each app follows Settings > Personalisation > Colours. |
| Chord: passcodes | Kept in Windows' Credential Manager. |
| Chord: media keys | Work as key presses. There is no MPRIS panel on Windows. |
| Chord: CDs | Discs (import and burning) stay a Linux feature. GStreamer on Windows has no CD source. |
| Reel: recording | Records the screen or a window through Direct3D 11 capture, the camera through Media Foundation and the microphone through WASAPI. |
| Show: recording | Records the screen through ffmpeg's desktop capture. |
| Old formats | `.doc`, `.xls` and `.ppt` open through LibreOffice when it is installed, as on Linux. |
| Fonts | Carlito, Liberation and STIX Two Math come with the suite. They are available to the apps only and aren't installed for the rest of Windows. |

## The files here

| File | What it is |
|---|---|
| `build.cmd`, `build.sh` | The build. |
| `stage.py` | Copies the runtime out of MSYS2, and makes the MSI (with wixl from msitools). |
| `launcher.c` | The small program behind each Start menu entry. It sets up the runtime and starts the app. |
| `files/folio-env.txt` | What that setup is. The launchers and the tests both read it. |
| `files/sitecustomize.py` | Makes the bundled fonts available to the apps. |
| `test.cmd`, `test-windows.py` | The checks. |
| `fonts/`, `dicts/`, `icons/` | The fonts, English dictionaries and app icons that ship in the MSI, with their licences. |
