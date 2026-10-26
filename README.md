# Folio Suite

Things that span the apps: one command for every app's tests, the suite package and its
local apt repository.

## Tests

```
./run-tests.sh              # the installed apps, with the test scripts from their source trees
./run-tests.sh --source     # the source trees, engines' unit tests included
./run-tests.sh --quick --only gable,suite
```

Set `SHEETS_SRC`, `DRAW_SRC` and `GABLE_SRC` if the sources aren't in `~/src`. A summary table
lists every test file with its number of checks and failures; the exit code is 0 only when all
passed. `tests/clipboard_chain.sh` copies Gable's view into Draw, Draw's picture into Sheets,
and checks the HTML table a Sheets range offers other programs.
