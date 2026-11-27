/* The Windows launcher for one Folio app (FolioPage.exe, folio-page.exe and so on).

   Folio's apps run on the runtime the installer puts beside them (Python, GTK, GStreamer, Qt), and
   they need to be told where it is. The launcher reads bin\folio-env.txt (KEY=VALUE lines, with
   %ROOT% for the installation folder and %NAME% for any variable already set), sets those for
   this app, starts the app with the arguments it was given, waits for it and returns its exit
   code. Standard input and output are passed on, so `folio-reel --render ...` works from a
   console or from another app.

   Built once per app with these defines (see build.sh):
     APP_NAME     "Folio Page"           for messages
     APP_PYMOD    "folio"                a Python app: runtime\bin\pythonw.exe -m APP_PYMOD
     APP_PYPATH   "apps\\page"           its code, relative to the installation folder
     APP_EXE      "bin\\folio-gable.exe" a native app instead of a Python one
     APP_CONSOLE  1                      a console program, starting python.exe rather than pythonw.exe */
#define WIN32_LEAN_AND_MEAN
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

#define W2(x) L##x
#define W(x) W2(x)

static wchar_t root[MAX_PATH];

static void fail(const wchar_t* what) {
    wchar_t msg[1200];
    _snwprintf(msg, 1200, L"%ls couldn't start: %ls\n\nReinstalling Folio Studio puts it right.", W(APP_NAME), what);
    msg[1199] = 0;
    MessageBoxW(NULL, msg, W(APP_NAME), MB_ICONERROR | MB_OK);
}

/* %ROOT% and %NAME% in a value, filled in */
static void expand(const wchar_t* in, wchar_t* out, size_t cap) {
    size_t o = 0;
    while (*in && o + 1 < cap) {
        if (*in == L'%') {
            const wchar_t* end = wcschr(in + 1, L'%');
            if (end && end > in + 1) {
                wchar_t name[128];
                size_t n = (size_t)(end - in - 1);
                if (n < 128) {
                    wmemcpy(name, in + 1, n);
                    name[n] = 0;
                    const wchar_t* val = NULL;
                    wchar_t buf[32768];
                    if (wcscmp(name, L"ROOT") == 0) val = root;
                    else if (GetEnvironmentVariableW(name, buf, 32768) > 0) val = buf;
                    if (val) {
                        for (; *val && o + 1 < cap; val++) out[o++] = *val;
                    }
                    in = end + 1;
                    continue;
                }
            }
        }
        out[o++] = *in++;
    }
    out[o] = 0;
}

static int load_env(void) {
    wchar_t path[MAX_PATH];
    _snwprintf(path, MAX_PATH, L"%ls\\bin\\folio-env.txt", root);
    path[MAX_PATH - 1] = 0;
    FILE* f = _wfopen(path, L"rb");
    if (!f) return 0;
    char line[8192];
    while (fgets(line, sizeof line, f)) {
        size_t n = strlen(line);
        while (n && (line[n - 1] == '\n' || line[n - 1] == '\r')) line[--n] = 0;
        if (!n || line[0] == '#') continue;
        wchar_t wl[8192], val[32768];
        if (!MultiByteToWideChar(CP_UTF8, 0, line, -1, wl, 8192)) continue;
        wchar_t* eq = wcschr(wl, L'=');
        if (!eq) continue;
        *eq = 0;
        expand(eq + 1, val, 32768);
        SetEnvironmentVariableW(wl, val);
    }
    fclose(f);
    return 1;
}

/* the arguments this launcher was given, as one string (argv[0] left out) */
static const wchar_t* own_args(void) {
    const wchar_t* c = GetCommandLineW();
    int quoted = 0;
    while (*c && (quoted || (*c != L' ' && *c != L'\t'))) {
        if (*c == L'"') quoted = !quoted;
        c++;
    }
    while (*c == L' ' || *c == L'\t') c++;
    return c;
}

static int run(void) {
    /* the installation folder: this program is in <root>\bin */
    if (!GetModuleFileNameW(NULL, root, MAX_PATH)) return 1;
    for (int up = 0; up < 2; up++) {
        wchar_t* s = wcsrchr(root, L'\\');
        if (s) *s = 0;
    }
    if (!load_env()) {
        fail(L"bin\\folio-env.txt is missing.");
        return 1;
    }
    SetEnvironmentVariableW(L"FOLIO_ROOT", root);

    static wchar_t line[32768];
    const wchar_t* args = own_args();
#ifdef APP_EXE
    _snwprintf(line, 32768, L"\"%ls\\%ls\" %ls", root, W(APP_EXE), args);
#else
    wchar_t pp[32768], old[32768];
    DWORD had = GetEnvironmentVariableW(L"PYTHONPATH", old, 32768);
    _snwprintf(pp, 32768, L"%ls\\%ls;%ls\\lib\\python%ls%ls", root, W(APP_PYPATH), root, had ? L";" : L"", had ? old : L"");
    pp[32767] = 0;
    SetEnvironmentVariableW(L"PYTHONPATH", pp);
#ifdef APP_CONSOLE
    const wchar_t* py = L"python.exe";
#else
    const wchar_t* py = L"pythonw.exe";
    /* where the app's output goes (sitecustomize.py), so a crash leaves something to read */
    static wchar_t log[MAX_PATH];
    wchar_t local[MAX_PATH];
    if (GetEnvironmentVariableW(L"LOCALAPPDATA", local, MAX_PATH)) {
        _snwprintf(log, MAX_PATH, L"%ls\\Folio Studio\\logs\\%ls.log", local, W(APP_NAME));
        log[MAX_PATH - 1] = 0;
        SetEnvironmentVariableW(L"FOLIO_LOG", log);
    }
#endif
    _snwprintf(line, 32768, L"\"%ls\\runtime\\bin\\%ls\" -m %ls %ls", root, py, W(APP_PYMOD), args);
#endif
    line[32767] = 0;

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof si);
    si.cb = sizeof si;
    HANDLE in = GetStdHandle(STD_INPUT_HANDLE), out = GetStdHandle(STD_OUTPUT_HANDLE), err = GetStdHandle(STD_ERROR_HANDLE);
    if ((in && in != INVALID_HANDLE_VALUE) || (out && out != INVALID_HANDLE_VALUE) || (err && err != INVALID_HANDLE_VALUE)) {
        si.dwFlags = STARTF_USESTDHANDLES;
        si.hStdInput = in;
        si.hStdOutput = out;
        si.hStdError = err;
    }
    wchar_t wd[MAX_PATH];
    DWORD wl = GetCurrentDirectoryW(MAX_PATH, wd);
    /* started by a window program (folio-reel.exe by Show, say), there is no console to share, and
       a console program would open a window of its own: CREATE_NO_WINDOW keeps it hidden */
    DWORD flags = GetConsoleWindow() ? 0 : CREATE_NO_WINDOW;
    if (!CreateProcessW(NULL, line, NULL, NULL, TRUE, flags, NULL, wl ? wd : NULL, &si, &pi)) {
        wchar_t why[600];
        _snwprintf(why, 600, L"Windows wouldn't start it (error %lu).", GetLastError());
        why[599] = 0;
        fail(why);
        return 1;
    }
    CloseHandle(pi.hThread);
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
#if !defined(APP_EXE) && !defined(APP_CONSOLE)
    if (code != 0 && log[0]) {
        wchar_t msg[1200];
        _snwprintf(msg, 1200, L"%ls stopped unexpectedly (code %lu).\n\nWhat it reported is in\n%ls", W(APP_NAME), code, log);
        msg[1199] = 0;
        MessageBoxW(NULL, msg, W(APP_NAME), MB_ICONERROR | MB_OK);
    }
#endif
    return (int)code;
}

/* the window programs (the Start menu's) and the console ones (folio-page.exe and the rest,
   for scripts and for the apps to start each other) */
#ifdef APP_CONSOLE
int wmain(void) { return run(); }
#else
int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, PWSTR cmd, int show) {
    (void)inst; (void)prev; (void)cmd; (void)show;
    return run();
}
#endif
