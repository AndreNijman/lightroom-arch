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

`make` builds **four** binaries (needs `x86_64-w64-mingw32-gcc` and
`i686-w64-mingw32-gcc`); `.exe`s are gitignored:

| binary | bitness |
|--------|---------|
| `httptest.exe`, `httptest-async.exe` | x86_64 |
| `httptest32.exe`, `httptest-async32.exe` | i386 |

## What they showed — the bug is 32-bit-specific

`Set-up.exe` is a `PE32 i386` binary, and Wine ships a separate
`i386-windows` `secur32` from `x86_64-windows`. That is the variable:

- **64-bit** probes (`httptest.exe`, `httptest-async.exe`) — **pass**
  100% against every endpoint the installer uses (`cc-api-data.adobe.io`,
  `lcs-cops.adobe.io`, `ccmdls.adobe.com`), sync / async / 8-way.
- **32-bit** probes (`httptest32.exe`) — **fail** 100% with
  `WinHttpSendRequest err=12157` (`ERROR_WINHTTP_SECURE_CHANNEL_ERROR`),
  exactly the installer's wall. A `+secur32` trace shows
  `schan_handshake FATAL ALERT: 20 Bad record MAC` — the server rejects
  the 32-bit client's handshake.

So the wall is an in-scope, reproducible **32-bit Wine `secur32` bug** —
not Adobe-side (`gnutls-cli`, Wine's own TLS library, completes the
handshake fine). `httptest32.exe` is the minimal repro. Exact defective
line not yet pinned — see `docs/attempt-17-cc-desktop.md`.

```sh
# 64-bit: passes;  32-bit: reproduces err=12157
wine httptest.exe   cc-api-data.adobe.io /ingest
wine httptest32.exe cc-api-data.adobe.io /ingest
```
