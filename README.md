# Folio Studio

Folio Studio (formerly Folio Suite) is the six Folio apps together: Folio Page (word processor,
formerly Writer), Folio Sheet (spreadsheet, formerly Sheets), Folio Show (presentations, formerly
Deliver), Folio Post (mail and calendar), Folio Draw (pictures and embroidery) and Folio Gable (3D
modelling). This repository holds what spans the apps: the installer and its local apt
repository, one command for every app's tests, and the code the apps share.

## Install

```
sh folio-studio-<version>-installer.run              # install or update everything
sh folio-studio-<version>-installer.run --old-formats  # also LibreOffice's converter for old formats
sh folio-studio-<version>-installer.run --repo-only    # only refresh the local repository
sh folio-studio-<version>-installer.run --remove       # take it all off again
```

An existing Folio Suite install is moved over: the old repository and key are replaced, and the
old package names (folio-suite, folio-writer, folio-sheets, folio-deliver) become transitional
packages, so the old commands keep working.

## Tests

```
./run-tests.sh              # the installed apps, with the test scripts from their source trees
./run-tests.sh --source     # the source trees, engines' unit tests included
./run-tests.sh --quick --only gable,suite
tests/machines.sh           # run-tests.sh on every release test machine (22.04, 22.04 without LibreOffice, 24.04)
tests/wl.sh CMD...          # run a test as a Wayland client (Weston inside the Xvfb)
```

Set `WRITER_SRC`, `SHEETS_SRC`, `DELIVER_SRC`, `POST_SRC`, `DRAW_SRC` and `GABLE_SRC` if the
sources aren't in `~/src`. A summary table lists every test file with its number of checks and
failures; the exit code is 0 only when all passed.

## Shared code

`shared/ribbon.py` and `shared/fontfix.py`, and `tests/themecheck.py`, are the one copy of code
several apps carry. `tools/sync_shared.sh` copies them into the apps; `--check` fails when an app's
copy differs.

## Releases

Each app's release run lives in its repository as `tools/release.sh` (Sheet: `tools/release_installed.sh`
after its source tests). A run builds the app, runs its tests from source, builds the .deb and tests
the installed package on the release test machines: chroots of Ubuntu 22.04 (`/srv/jammy`), 22.04
without LibreOffice (`/srv/nolo`) and 24.04 (`/srv/noble`), each with an Xvfb display, plus a Wayland
pass on 24.04 through `tests/wl.sh`. `tools/mounts.sh` prepares the chroots. The suite itself is built
with `packaging/build-suite.sh <folder of debs> <output folder>`.
