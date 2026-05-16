# repro-winhttp-adobe — Wine WinHTTP/TLS diagnostic harness

Diagnostic tools for the attempt-17 networking wall: the Adobe CC
installer (`Set-up.exe`) cannot complete any HTTPS request inside Wine
(`-1` / `HTTP_Status:0`), so its sign-in workflow parks. See
`docs/attempt-17-cc-desktop.md`.

## Tools

| File | What it does |
|------|--------------|
| `httptest.c` | Minimal **synchronous** WinHTTP HTTPS GET. `httptest.exe <host> <path> [threads]` — prints the HTTP status or the failing WinHTTP call + error. |
| `httptest-async.c` | Same, **asynchronous** (`WINHTTP_FLAG_ASYNC` + status callback), one shared session for N concurrent requests — mirrors how `Set-up.exe` drives WinHTTP. |

Build: `make` (needs `x86_64-w64-mingw32-gcc`). `.exe`s are gitignored.

## What they showed

These are **controls**, not a failing repro. Run under the CC Wine prefix
they both **succeed** against every endpoint the installer uses
(`cc-api-data.adobe.io`, `lcs-cops.adobe.io`, `ccmdls.adobe.com`) — sync,
async, and 6–8-way concurrent — returning real HTTP responses.

`Set-up.exe`'s own WinHTTP connections, by contrast, fail 100% at the TLS
handshake. Since a minimal WinHTTP client and `gnutls-cli` (Wine's own
`libgnutls`) both complete the handshake to the same servers, the wall is
**not** Adobe-side and **not** a dead Wine TLS stack — it is a Wine
`secur32`/`winhttp` bug that only triggers inside the installer's process.
Exact defect not yet pinned — see `docs/attempt-17-cc-desktop.md`.

```sh
# examples
wine httptest.exe       ccmdls.adobe.com /AdobeESD/CCD/healthcheck
wine httptest-async.exe cc-api-data.adobe.io /ingest 6
```
