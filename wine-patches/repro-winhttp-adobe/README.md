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

`Set-up.exe` is a `PE32 i386` binary. That is the variable:

- **64-bit** probes (`httptest.exe`, `httptest-async.exe`) — **pass**
  100% against every endpoint the installer uses (`cc-api-data.adobe.io`,
  `lcs-cops.adobe.io`, `ccmdls.adobe.com`), sync / async / 8-way.
- **32-bit** probes (`httptest32.exe`) — **fail** 100% with
  `WinHttpSendRequest err=12157` (`ERROR_WINHTTP_SECURE_CHANNEL_ERROR`),
  exactly the installer's wall.

> **NOTE — this is a *symptom* repro, not the root cause.** It was first
> read as a "32-bit Wine `secur32` bug" — that was WRONG. The real defect
> is in the host's 32-bit `nettle` (`lib32-nettle 4.0`), reproduced with
> **no Wine at all** by `repro/nettle-i386/`. `httptest32.exe` is still
> useful — it is what the Adobe installer actually hits — but the
> Wine-free `repro/nettle-i386/ntls-handshake.c` is the one to attach to
> an upstream bug report. See `docs/attempt-17-cc-desktop.md`
> "Re-diagnosis".

```sh
# 64-bit: passes;  32-bit: reproduces err=12157
wine httptest.exe   cc-api-data.adobe.io /ingest
wine httptest32.exe cc-api-data.adobe.io /ingest
```
