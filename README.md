# Folio Studio

Folio Studio (formerly Folio Suite) is the seven Folio apps together: Folio Page (word processor,
formerly Writer), Folio Sheet (spreadsheet, formerly Sheets), Folio Show (presentations, formerly
Deliver), Folio Draw (pictures and embroidery), Folio Gable (3D modelling), Folio Chord (music,
internet radio and podcasts) and Folio Reel (video editing). Folio Cork (diagrams and boards) was
discontinued on 26 November 2026 (Studio 1.27.0); its diagrams already in Page, Sheet and Show
documents stay as pictures. This repository holds what spans the
apps: the installer and its signed apt repository, one command for every app's tests, and the code the apps share.

Studio 1.13.0 was published on 7 November and withdrawn the same evening. It replaced Page, Sheet,
Show, Chord, Gable and Reel with the Rust rewrites, and those rewrites are not yet at parity with
the apps they replaced: Chord shipped with no menu bar at all. The package source is back at
1.12.5. A rewrite does not take over from a shipping app again until it has been compared against
that app, feature by feature, and the comparison is written down.

## Install

```
sh folio-studio-<version>-installer.run              # install or update everything
sh folio-studio-<version>-installer.run --old-formats  # also LibreOffice's converter for old formats
sh folio-studio-<version>-installer.run --repo-only    # only set up the package source
sh folio-studio-<version>-installer.run --remove       # take it all off again
```

An existing Folio Suite install is moved over: the old repository and key are replaced, and the
old package names (folio-suite, folio-writer, folio-sheets, folio-deliver) become transitional
packages, so the old commands keep working.

Folio Post is discontinued (Studio 1.11.0). The installer removes it, and the package source carries an empty
folio-post that replaces it on machines that only update through the Software Updater. Mail and
settings in the home folder are left alone.

The installer installs from its own copy of the packages (so it works offline), then points apt at
the online package source, https://akeilan.github.io/FolioStudio/ (GitHub Pages, `gh-pages`
branch). From then on new versions arrive through the Software Updater. If that address can't be
reached at install time, the local copy is kept alongside it until the next run.

## Windows

`windows/` builds all seven apps into one MSI for Windows 10 and 11 (64-bit), on a Windows PC with
MSYS2: double-click `windows\build.cmd`, then install the MSI from the Desktop and run
`windows\test.cmd`. See [windows/README.md](windows/README.md). The Windows build is tested by the
Product Owner on Windows 11; the Linux release runs don't touch it.

## Tests

```
./run-tests.sh              # the installed apps, with the test scripts from their source trees
./run-tests.sh --source     # the source trees, engines' unit tests included
./run-tests.sh --quick --only gable,suite
tests/machines.sh           # run-tests.sh on every release test machine (22.04, 22.04 without LibreOffice, 24.04)
tests/wl.sh CMD...          # run a test as a Wayland client (Weston inside the Xvfb)
```

Set `WRITER_SRC`, `SHEETS_SRC`, `DELIVER_SRC`, `DRAW_SRC` and `GABLE_SRC` if the
sources aren't in `~/src`. A summary table lists every test file with its number of checks and
failures; the exit code is 0 only when all passed.

## Shared code

`shared/ribbon.py` and `shared/fontfix.py`, and `tests/themecheck.py`, are the one copy of code
several apps carry. `tools/sync_shared.sh` copies them into the apps; `--check` fails when an app's
copy differs.

## Testing policy

A release must pass on Linux: Ubuntu 22.04 and 24.04, X11 and Wayland. That is the whole bar, and
every app's `tools/release.sh` runs exactly that — source tests and the installed package on
`/srv/jammy`, `/srv/nolo` and `/srv/noble`, then a Wayland pass on 24.04.

Other processors and other operating systems are not part of a release, and are not tested at all:
any port beyond Zorin OS and Linux Mint is a bridge crossed when we get there (Product Owner,
2026-11-06). The portable base keeps the door open for them — the other-CPU and Raspberry Pi checks
run when asked for, with `PORTS=1 tools/release.sh`, and no release run touches Windows, macOS or
wine. The Windows MSI (Studio 1.29.0 on) is the exception the Product Owner asked for: it is built
and tested on his Windows 11 PC, not here. The suite is developed and used on Zorin OS, and Linux Mint is the other system it is meant
for; both are Ubuntu-based, so the 22.04 and 24.04 machines are the bar.

## Releases

Each app's release run lives in its repository as `tools/release.sh` (Sheet: `tools/release_installed.sh`
after its source tests). A run builds the app, runs its tests from source, builds the .deb and tests
the installed package on the release test machines: chroots of Ubuntu 22.04 (`/srv/jammy`), 22.04
without LibreOffice (`/srv/nolo`) and 24.04 (`/srv/noble`), each with an Xvfb display, plus a Wayland
pass on 24.04 through `tests/wl.sh`. `tools/mounts.sh` prepares the chroots. The suite itself is built
with `packaging/build-suite.sh <folder of debs> <output folder>`, and published with
`tools/publish.sh <output folder>`, which puts the new signed repository on the `gh-pages` branch
as an ordinary commit (nothing is force-pushed). The signing key lives in `~/.folio-suite-signing` on the release machine; the Product
Owner keeps a copy (`folio-studio-signing-key.asc`, import with `gpg --import`).

## Licence

MIT — see [LICENSE](LICENSE). Folio Studio is free to use, read, change and pass
on, including in your own products. The bundled fonts (Carlito, Liberation) are
under the SIL Open Font License 1.1 and carry their own licences.
