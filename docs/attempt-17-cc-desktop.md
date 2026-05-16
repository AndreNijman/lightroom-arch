# Attempt 17 — Full Creative Cloud Desktop app, installer-driven (no rsync)

Goal: ship a one-effort install — anyone who clones the repo runs one
script, the **Adobe Creative Cloud Desktop** app installs and runs under
Wine, and Lightroom is installed *through* it. No rsync from a Windows
partition, no dual-boot dependency.

Working prefix: `~/.wine_cc` (fresh; the rsync prefix `~/.wine_adobe`
is left intact as a fallback).

## Progress

1. **Clean prefix built** — `~/.wine_cc`, win64, on the bundled
   PhialsBasement patched Wine 10.0 (`~/opt/wine-adobe`). `wineboot
   --init` succeeded. `UseXVidMode=N` set in `user.reg` *before* any
   other Wine call (the XVidMode assertion still crashes patched Wine on
   Hyprland/XWayland). Wine Gecko 2.47.4 auto-installed. `libvkd3d-1.dll`
   / `libvkd3d-shader-1.dll` copied from `default_pfx` into
   system32/syswow64.

2. **TLS is NOT the blocker.** attempt-2 blamed the blank installer on a
   TLS failure ("can't fetch UI assets"). Re-tested: the Adobe analytics
   POST (`dunamis` → `https://cc-api-data.adobe.io/ingest`) **completes
   the TLS handshake** and gets a real HTTP response (500, because Wine's
   `BCryptExportKey` fails to encrypt the analytics payload —
   `0xc0000023`, non-fatal). And the installer's UI assets are **not
   downloaded** at all — `Set-up.exe` extracts them locally to
   `%TEMP%\{GUID}\` (`index.html`, `index.css`, `CCDInstaller.js`).
   TLS works; the blank screen has a different cause.

3. **Root cause of the blank teal installer window — found.**
   `Set-up.exe`'s UI is a React app (`CCDInstaller.js`, 1.3 MB webpack
   bundle) hosted in an embedded IE **WebBrowser control**, i.e. Wine's
   `mshtml`. Confirmed from `/proc/<pid>/maps`: `mshtml.dll` + Wine Gecko
   `xul.dll` are loaded; **no `libcef`** — the installer does not use CEF
   on Wine.

   `index.html` carries `<meta http-equiv='X-UA-Compatible'
   content='chrome=1'>`. Wine logs `process_meta_element Unsupported
   document mode L"chrome=1"`.

   The decisive fact: Wine's `mshtml` uses Gecko only for DOM/layout/CSS
   — **JavaScript runs through Wine's own `jscript.dll`**, an ES5-era
   JScript engine, not Gecko's SpiderMonkey. `CCDInstaller.js` is a
   modern (ES6+) webpack bundle. `jscript.dll` fails to parse it:

   ```
   jscript:set_error_location source L"...webpack bootstrap..."
   jscript:leave_script 800a03ea          (JScript error 1002 = syntax error)
   mshtml:ActiveScriptSite_OnScriptError
   mshtml:parse_elem_text <<< 800a03ea
   ```

   React never mounts → `<div id='root'>` stays empty → the window
   paints only its teal background. This is the "Adobe blue screen".

## The real problem

Wine `mshtml` + `jscript.dll` (ES5) cannot run Adobe's ES6+ React
installer bundle. The PhialsBasement patches improve `jscript`/`mshtml`
but not enough for this bundle. Fix options under evaluation:

- **A** — close the `jscript.dll` ES6 gap (patch Wine `jscript`).
- **B** — force the installer to use the bundled **CEF** (Chromium)
  instead of `mshtml`; CEF runs the React bundle natively.
- **C** — silent / headless install: if `Set-up.exe` (or the HD/Adobe
  Admin-Console installer) can install with no UI, the React render is
  moot.
- **D** — transpile `CCDInstaller.js` to ES5 before `mshtml` loads it.

## Breakthrough — the JS parse wall is cleared

The blank screen was *not* a missing `jscript` feature. Wine's `mshtml`
gates the `jscript` language version on the document's **compat mode**.
`index.html` carries `<meta http-equiv='X-UA-Compatible'
content='chrome=1'>`; Wine can't parse `chrome=1`, falls back to compat
**mode 2** (IE7), and in mode 2 `jscript` rejects `class` / `let` /
template literals — `SyntaxError 800a03ea`.

Fix: rewrite that meta to `content='IE=11'`. Wine then uses compat
**mode 6** (IE11), `jscript` runs in ES6 mode, and `CCDInstaller.js`
parses with **zero syntax errors**. Confirmed: React mounts, React
Spectrum initialises (`cci-root … react-spectrum-provider spectrum
spectrum--light`), the app builds its DOM.

`FEATURE_BROWSER_EMULATION` in the registry does **not** work — Wine
`mshtml` ignores it; the `<meta>` is authoritative. The installer
extracts `index.html` to `%TEMP%\{GUID}\` fresh each run, so the install
script rewrites the meta in that file between extraction and the
WebBrowser navigation (a short, reliable window).

## Remaining wall (post-parse)

With JS running, the installer window still shows only the teal
splash. The decisive observations:

- React mounts, React Spectrum initialises, the DOM is built (2.6 M
  lines of `mshtml`/`jscript` trace, `HTMLDocument7_createElement
  "div"`, `react-spectrum-provider`).
- The app renders a `spectrum-CircleLoader` — a **loading spinner** — and
  tags its root `cci-root mac`. It sniffs the user agent (`\bMSIE\b`,
  `\bTrident\b`, `isWinPlatform`) and carries
  `cci.error.product.platformIneligible.macarm64` strings.
- A static `position:fixed` red `<div>` injected into `<body>` (a paint
  probe) is **also** invisible.

Best diagnosis: `Set-up.exe` paints a native teal splash window, embeds
the WebBrowser behind it, and only lifts the splash once the React app
signals "UI ready". The app is **stuck in its loading state** — most
likely platform mis-detection (Wine's IE11 user-agent does not look like
Windows IE to the app) and/or the product-catalog fetch — so the "ready"
signal never fires and the splash never lifts. The embedded WebBrowser
(and the red probe inside it) stay covered. It is *not* a Wine paint
bug: the DOM renders, it is simply occluded.

So the chain still to break: platform detection → catalog fetch →
sign-in → the actual install. Each is its own step; then the installed
**CC Desktop app** has its *own* (CEF, not mshtml) render path, and a
freshly-installed Lightroom needs its binary patches re-derived against
the new build. This is multi-session work — see the status note below.

### Platform detection — why `cci-root mac`

Decompiling `CCDInstaller.js`: the root class is
`"cci-root ".concat(a?"win":"mac")` where `a = isWinPlatform`, and
`isWinPlatform` is set once from the init context as
`"win" === t.platform`. `t.platform` is **not** read from
`navigator.platform` — it is data the *native* `Set-up.exe` host feeds
into the React app as init context, so the React app defaults to `mac`.

**Superseded — see "Step 5 investigation" below.** This section earlier
concluded the native→JS init bridge / `window.external` host-object gap
was "the real wall". The WAM-log evidence in the step-5 section disproves
that: WAM's back-end workflow reaches `START_SIGNIN_WORKFLOW`
*independently* of the React platform value and parks there on a Wine
networking failure. `cci-root mac` is cosmetic, not the blocker.

## What this attempt ships

`scripts/install-cc-desktop.sh` — a clean, rsync-free, one-command setup:
builds `~/.wine_cc`, applies the XVidMode / vkd3d / patched-DLL fixes,
sets the registry tweaks, and launches the CC Desktop installer with the
`index.html` meta rewritten to `IE=11` via an `inotifywait` watcher (no
polling race). It gets a user from a clean machine to a *running* CC
installer with no Windows partition involved — the JS parse wall is
gone. The loading-state wall above is not yet solved.

The `chrome=1` → `IE=11` finding is a genuine, self-contained Wine
interaction worth reporting upstream: Wine `mshtml` should not drop to
IE7 compat mode (and thus ES5 `jscript`) for a document whose only
`X-UA-Compatible` directive is the unrecognised `chrome=1`.

## Primary-source check — the diagnosis above is wrong; the real fix is cleaner

Re-checked against Wine 10.0 source (`~/wine-build/wine-src/dlls/mshtml`)
before patching. The earlier "`chrome=1` forces IE7" story does not
survive contact with the code.

**1. `chrome=1` does not force anything — it is a parse no-op.**
`parse_ua_compatible()` (`mutation.c:506`) returns `COMPAT_MODE_INVALID`
for any content that does not start with `IE=`. `process_meta_element()`
(`mutation.c:584`) then simply does *not* call `set_document_mode()` and
logs the `FIXME("Unsupported document mode ...")`. The meta is ignored;
it never lowers the mode.

**2. IE7 is the *doctype default*, not a consequence of the meta.**
The IE7 drop happens in the doctype-node handler
(`mutation.c:919-948`): when a standards-mode doctype is seen and the
mode is still `COMPAT_MODE_QUIRKS`, Wine sets `COMPAT_MODE_IE7` — and
only bumps to IE11 if `is_iexplore()` *and* the URL is in the Internet
zone. `Set-up.exe` is not `iexplore.exe`, so it gets IE7. A page with
**no `X-UA-Compatible` meta at all** lands in IE7 exactly the same way.
This is, in fact, Windows-faithful: a real embedded WebBrowser control
in a non-`iexplore` host with no opt-in also defaults to IE7.

Therefore the goal's literal step 4 ("make an unknown token keep IE11
mode") would make Wine *diverge* from Windows, not match it — out of
scope by the project's own rule.

**3. The real Windows mechanism is `FEATURE_BROWSER_EMULATION`, and
Wine ignores it.** `Set-up.exe` imports only `KERNEL32`, `urlmon`,
`WS2_32` — it is a `urlmon`/`ieframe` WebBrowser-control host (confirmed:
`WINEDEBUG=+loaddll` shows it loading `ieframe.dll` + `mshtml.dll` +
`jscript.dll`, never `libcef.dll`). The `libcef.dll`/Chromium files in
`installers/ACCCx_extracted/` are dated 2026-05-15 — leftover cruft from
attempt-17's abandoned "option B", **not** part of the Adobe installer
(original installer files are dated 2023-02-19: `Set-up.exe` +
`packages/`).

Decisive test — run `Set-up.exe` in a prefix with the
`FEATURE_BROWSER_EMULATION` key removed entirely:

```
[Software\\Microsoft\\Internet Explorer\\Main\\FeatureControl\\FEATURE_BROWSER_EMULATION]
"Set-up.exe"=dword:00002af9
```

`Set-up.exe` **writes that key for itself** (`0x2af9` = 11001 = IE11
mode). This is the standard, documented Windows opt-in for embedded
WebBrowser controls. On real Windows, IE honours it and the control
runs in IE11 → the ES6 React bundle parses. Wine's `mshtml` reads
`FEATURE_BROWSER_EMULATION` **nowhere** — the comment at
`mutation.c:928-933` explicitly acknowledges the key is unimplemented.

**Conclusion.** The Adobe installer already does the correct, standard
Windows thing (sets `FEATURE_BROWSER_EMULATION` for itself). The Wine
gap is that `mshtml` ignores that key. The Windows-faithful, in-scope
fix is to **implement `FEATURE_BROWSER_EMULATION` in Wine `mshtml`**.
That fix:

- runs Adobe's installer completely unmodified (no `index.html`
  rewrite — the `chrome=1`→`IE=11` crutch is deleted, not reimplemented);
- needs no registry pre-seeding by the install script (`Set-up.exe`
  writes the key itself);
- makes Wine behave exactly as Windows does.

This supersedes step 4's stated approach.

## Implemented — Wine mshtml honours FEATURE_BROWSER_EMULATION

`wine-patches/mshtml-feature-browser-emulation.patch` (prebuilt
`mshtml-i386.dll` + `mshtml-x86_64.dll`).

`dlls/mshtml/mutation.c` gains `get_feature_browser_emulation()`: it reads
the `FEATURE_BROWSER_EMULATION` DWORD for the current process executable
(HKCU then HKLM) and maps it to a compat mode (7000→IE7 … 11000/11001→
IE11). The doctype-node handler now consults it *before* the `iexplore`
heuristic — an explicit per-exe opt-in wins. With no key present the
behaviour is byte-for-byte unchanged (a non-`iexplore` host still
defaults to IE7).

### Verification

Minimal non-Adobe repro — `wine-patches/repro-feature-browser-emulation/`
(a `urlmon` WebBrowser-control host `wbhost.exe` loading a `<!DOCTYPE
html>` page with a `let`/`const` snippet, printing `document.title`):

| `mshtml` | `FEATURE_BROWSER_EMULATION\wbhost.exe` | Output |
|----------|----------------------------------------|--------|
| stock    | `0x2af9` set | `TITLE=ES5-RAN` (key ignored → IE7, ES6 `SyntaxError`) |
| patched  | `0x2af9` set | `TITLE=ES6-OK` (→ IE11) |
| patched  | absent       | `TITLE=ES5-RAN` (unchanged IE7 default) |

Real installer — `Set-up.exe` on a prefix with the key *not* pre-seeded:
`Set-up.exe` writes `FEATURE_BROWSER_EMULATION\Set-up.exe=0x2af9` for
itself; patched `mshtml` logs `get_feature_browser_emulation … -> compat
mode 6`, `set_document_mode … 6`, and the React/webpack bundle parses
with **0** `jscript` syntax errors (stock: `set_document_mode … 2`, 6
syntax errors). First run is deterministic — `Set-up.exe` writes the key
before its WebBrowser navigates, so no registry pre-seeding is needed.

`scripts/install-cc-desktop.sh` now installs the patched `mshtml.dll` and
launches `Set-up.exe` with **no Adobe-shipped file touched**: the
`index.html` `chrome=1`→`IE=11` rewrite and its `inotifywait` watcher are
deleted, and `FEATURE_BROWSER_EMULATION` is no longer pre-seeded.

The post-parse loading-spinner wall is unchanged by this fix — see below.

## Step 5 investigation — the loading-spinner wall is NOT a host-object gap

The goal asked to investigate the loading-spinner wall as a Wine
*host-object* gap (Wine `mshtml` failing to deliver `window.external` /
the native→JS init context). The investigation **disproves** that
hypothesis. Primary evidence: the installer's own WAM log,
`drive_c/users/<u>/AppData/Local/Temp/CreativeCloud/ACC/WAM.log`.

WAM (the native installer back-end, `WAMB`) initialises and runs its
state machine cleanly — *independently of the React UI*:

```
Embedded json data not found in the binary        <- INFO, handled; harmless
Application pre initialized successfully
Application initialized successfully
WorkflowManager: ACQUIRE_LOCKS
WorkflowManager: CHECK_GENERAL_SYSTEM_REQUIREMENTS  <- system req check PASSES
WorkflowManager: CHECK_FOR_PROXY
WorkflowManager: CHECK_FOR_NETWORK
WorkflowManager: CHECK_ALREADY_INSTALLED_PRODUCT
WorkflowManager: SHOW_WELCOME_SCREEN
WorkflowManager: START_SIGNIN_WORKFLOW              <- reaches sign-in
```

So the earlier "platform mis-detection parks it on the spinner" /
"native→JS init bridge is the real wall" conclusion was wrong:

- `Embedded json data not found in the binary` is an **INFO** line, not
  an error — WAM handles it and reports *initialized successfully*. The
  generic `ACCCx` installer simply carries no embedded JSON.
- WAM passes `CHECK_GENERAL_SYSTEM_REQUIREMENTS` and reaches
  `START_SIGNIN_WORKFLOW`. If the platform were judged ineligible
  (`platformIneligible.*`), WAM would stop at the system-requirements
  state — it does not. The `cci-root mac` class and the
  `window.external`-not-found in `jscript` traces are real but
  **cosmetic**: the React shell renders, the back-end workflow does not
  depend on them.

The actual wall is **networking**. At `START_SIGNIN_WORKFLOW`:

```
NGLWrapper: GetSUSIURL API failed with -1 code and url-empty description
UserProfile: Failed to getSUSIUrl                  (retried 3x)
HTTPConnector: HEAD https://ccmdls.adobe.com:443/AdobeESD/CCD/healthcheck
HTTPConnector: The http request returned HTTP_Status:0
HTTPConnector: Received HTTP response: Response code = -1
WorkflowManager: showErrorAlert. Showing errorAlert for 206
```

Every Adobe HTTP request the installer's OOBE `HTTPConnector` and the NGL
licensing library make returns `-1` / `HTTP_Status:0` inside Wine. The
**same endpoints are fully reachable from the host** — native `curl`:

```
https://ccmdls.adobe.com/AdobeESD/CCD/healthcheck   -> 200  (TLS OK)
https://cc-api-data.adobe.io/ingest                 -> 403  (TLS OK)
https://ims-na1.adobelogin.com/ims/check/v6/token   -> 400  (TLS OK)
```

So the host is online and the endpoints work; the failure is **Wine-side
HTTP**, specific to the HTTP client OOBE/NGL use (distinct from the
`dunamis` analytics path, which attempt 2 found *does* complete its TLS
handshake — different HTTP stacks). The `GetIEProxyInfo ... error:12180`
(`ERROR_WINHTTP_AUTODETECTION_FAILED`, WPAD) is logged but is non-fatal.

### Verdict (per the goal's scope rule)

The loading-spinner wall is **not** an `mshtml`/host-object/`jscript`
problem and not solvable by feeding the installer a platform value (the
platform value is not what blocks it). It is a Wine `winhttp`/`wininet`/
`schannel` networking gap in the path the Adobe OOBE and NGL libraries
use. That is a separate investigation outside step 5's stated
"Wine host-object gap" scope. Per the goal: **stopping here and reporting
back rather than improvising a network workaround or a forced value.**

`scripts/install-cc-desktop.sh` therefore stays marked WORK IN PROGRESS:
it gets a clean machine to a CC installer whose React UI runs (JS parse
wall solved) but which cannot complete sign-in until the Wine networking
gap is addressed.

## Networking wall — diagnosed (Wine-side TLS, NOT Adobe-side)

Followed the "diagnose before patching" rule: classify the `-1` /
`HTTP_Status:0` failure as (a) Wine TLS/cert gap, (b) Wine winhttp
protocol gap, or (c) Adobe-side rejection — *before* touching Wine source.

### What the `-1` actually is

`WINEDEBUG=+winhttp,+secur32` on `Set-up.exe`: **every** TLS connection
the installer opens fails in `netconn_secure_connect` — 0 succeed. Two
shapes, both at handshake-completion time:

- `recv 7 bytes` → `InitializeSecurityContext ret 0x80090304`
  (`SEC_E_INTERNAL_ERROR`). The 7 bytes are a TLS record header + a
  2-byte payload, i.e. the server sent a **TLS alert**.
- `recv error 10054` (`WSAECONNRESET`) → `0x2f7d`
  (`ERROR_WINHTTP_SECURE_CHANNEL_ERROR`). The server **RST**s the socket.

Both happen *after* the client's second flight (CKE+CCS+Finished) is sent
— the server rejects the completed handshake. A server alert / RST right
after the client `Finished` is the signature of a **bad Finished MAC**:
the handshake transcript the client hashed differs from the server's.

### Ruling out (c) — Adobe-side rejection

Decisive, and it rules (c) out:

- `gnutls-cli` from the host — using **the exact `libgnutls` 3.8.13 that
  Wine's `secur32` loads** — completes the handshake to
  `cc-api-data.adobe.io` and `ccmdls.adobe.com`, TLS 1.2 and TLS 1.3,
  "certificate is trusted, Handshake was completed". The servers accept
  this TLS stack.
- A minimal non-Adobe WinHTTP client (`wine-patches/repro-winhttp-adobe/`,
  `httptest.c`) — plain Wine `winhttp` — completes the HTTPS request to
  **every** endpoint the installer uses (`cc-api-data.adobe.io`,
  `lcs-cops.adobe.io`, `ccmdls.adobe.com`) and gets a real HTTP response
  (403 — same status the host `curl` gets; 403 is just an unauthenticated
  bare GET). Tested single, 8-way concurrent, and async (`WINHTTP_FLAG_
  ASYNC`, `httptest-async.c`) — 100% success.

So Adobe's servers, Wine's TLS library, and Wine's `winhttp` in isolation
all work. **(c) is ruled out** — the wall is not geo/integrity/auth
rejection, and (correcting attempt 2) it is not a dead TLS stack either.

### Reproduced — the bug is 32-bit-specific

The first minimal clients (`httptest`, `httptest-async`) were built
**x86_64** and all succeeded — so the failure looked process-specific.
It is not. `Set-up.exe` is a **`PE32 i386`** binary; the 32-bit code
path is exercised independently of the 64-bit one. Rebuilding the same
probe 32-bit (`i686-w64-mingw32-gcc`) reproduces it cleanly:

| probe | bitness | result |
|-------|---------|--------|
| `httptest.exe` / `httptest-async.exe` | x86_64 | HTTP 200/403 — 100% pass (sync, async, 8-way concurrent) |
| `httptest32.exe` / `httptest-async32.exe` | **i386** | `WinHttpSendRequest err=12157` — **100% fail** |

`httptest32.exe` is an 8-line non-Adobe WinHTTP `GET` and fails every
time — a minimal repro of the installer's wall. `+secur32` trace of the
failing 32-bit handshake ends with `schan_handshake FATAL ALERT: 20 Bad
record MAC`.

> **NOTE — re-diagnosed 2026-05-16 (session 3). The earlier conclusion in
> this section, "(b) a Wine `secur32` bug", was WRONG.** It is corrected
> below. The Adobe-side ruling-out above still holds; the *attribution to
> Wine* did not. (Goal rule: "DO NOT assume this is a Wine bug." The
> earlier text broke that rule — see correction.)

### Re-diagnosis — the wall is a 32-bit `nettle` bug, not Wine

The "32-bit Wine `secur32` bug" claim was never confirmed against a
non-Wine baseline. It was, and it collapses.

**Test 1 — vary the cipher.** Pointing `httptest32.exe` at different
hosts changes the negotiated suite. Two distinct, deterministic 32-bit
failure modes appear, by curve:

| host | suite / KX | 32-bit | 64-bit |
|------|-----------|--------|--------|
| `cc-api-data.adobe.io`, `example.com`, `google.com` | ECDHE **X25519** + ChaCha20-Poly1305 | `err=12157`, `bad_record_mac` | OK |
| `www.microsoft.com`, `badssl.com` | ECDHE **NIST P-256/384** + AES-GCM | **hard abort** (see below) | OK |

The AES-GCM/NIST-curve case does not return a WinHTTP error at all — the
process **aborts** with a libc assertion:

```
ecc-random.c:62: _nettle_ecc_mod_random: Assertion `nbytes <= m->size * sizeof (mp_limb_t)' failed.
```

`ecc-random.c` / `_nettle_ecc_mod_random` is **`nettle`** source
(`libnettle.so.9`), a native Linux shared library. Wine does not — and
cannot — make `assert()` fire inside native `nettle` code; it merely
hosts the process. The crash is in `nettle`'s own ECC scalar generation.

**Test 2 — remove Wine entirely.** A 9-line **native** `gcc -m32` program
linking the system 32-bit GnuTLS (`repro/nettle-i386/ntls-handshake.c`),
no Wine in the process at all:

```
64-bit native:  HANDSHAKE OK: (TLS1.3)-(ECDHE-SECP256R1)-(AES-256-GCM)
32-bit native:  ecc-random.c:62: _nettle_ecc_mod_random: Assertion ... failed.
```

Identical assertion, zero Wine. **Wine is fully exonerated.** So is Adobe
and so is `mshtml`. The defect is in the host's 32-bit crypto stack.

### What is actually broken

- Packages: `nettle 4.0-1` / `lib32-nettle 4.0-1` (`libnettle.so.9.0`,
  `libhogweed.so.7.0`) and `gnutls 3.8.13` / `lib32-gnutls 3.8.13-3`
  (`libgnutls.so.30.42.0`). 64-bit and 32-bit are the *same upstream
  versions* — the only variable is ILP32 vs LP64.
- The 32-bit (`i386`) build of `nettle` 4.0 fails its own internal
  invariant in `_nettle_ecc_mod_random` (`nbytes <= m->size *
  sizeof(mp_limb_t)`): an `ecc_modulo` whose limb count `m->size` is
  inconsistent with the requested random byte count `nbytes`. On a NIST
  curve this trips the `assert()` and aborts; on X25519+ChaCha20 the
  outbound record's AEAD tag comes out wrong and the server answers
  `bad_record_mac`. Both are the same 32-bit crypto-stack defect.
- Candidate root causes (not pinned — out of scope this session):
  (1) a `nettle` 4.0 `i386` regression in ECC limb handling;
  (2) `lib32-nettle` 4.0 mis-detecting GMP's `mp_limb_t` size at build
  time (laying out `ecc_modulo` tables with 64-bit assumptions);
  (3) an ABI mismatch between `gnutls` 3.8.13 and the newer `nettle` 4.0
  (`libnettle.so.9`/`libhogweed.so.7`) that only manifests on ILP32.
  Pinning which one needs a `nettle` 4.0 i386 build with symbols — a
  task for the upstream maintainer, not this repo.

### Pinned — the exact defect (re-diagnosed 2026-05-16, session 4)

The defect is **not in `nettle` source** and **not in Wine**. It is the
Arch **`lib32-nettle` PKGBUILD**.

That PKGBUILD configures nettle with `--with-include-path=/usr/lib32/gmp`.
**nettle 4.0 deleted that option** — nettle `NEWS`: *"The unusual
configure options `--with-lib-path` and `--with-include-path` has been
deleted. Use CFLAGS and LDFLAGS."* `configure` silently ignores the
unknown flag (`WARNING: unrecognized options: --with-include-path`).

So the 32-bit build never sees the 32-bit `gmp.h` (`GMP_LIMB_BITS == 32`)
that `lib32-gmp` ships at `/usr/lib32/gmp/gmp.h`. nettle's `configure`
runs `AC_COMPUTE_INT(GMP_NUMB_BITS, [#include <gmp.h>])`, reads the
**64-bit** `/usr/include/gmp.h` instead, and sets `NUMB_BITS=64`. The
`eccdata` build tool then generates every ECC constant table for 64-bit
limbs. In the 32-bit library `struct ecc_modulo.size` is half the real
limb count (P-256: 4, not 8), so at `ecc-random.c:62`
`nbytes=32 > m->size*sizeof(mp_limb_t)=16` → the assertion aborts.

Verified directly: `configure` with `--with-include-path` →
`checking for GMP limb size... 64 bits`; with `CPPFLAGS=-I/usr/lib32/gmp`
→ `... 32 bits`.

### The fix — `patches/nettle/`

Pass the 32-bit gmp include directory via `CPPFLAGS`, as nettle 4.0
documents. `patches/nettle/lib32-nettle-cppflags-gmp32.patch` (and the
full corrected `patches/nettle/PKGBUILD`):

```
-    --enable-shared --with-include-path=/usr/lib32/gmp
+    --enable-shared
+    # with: export CPPFLAGS="-I/usr/lib32/gmp${CPPFLAGS:+ $CPPFLAGS}"
```

No `nettle` source is changed. **No assertion or bounds check is
weakened.** The fix only makes the 32-bit build a normal 32-bit nettle
build — the configuration nettle ships and tests on every genuine 32-bit
platform. The assertion is then *legitimately* satisfied (`32 <= 8*4`).

`lib32-nettle 4.0-1` was rebuilt with the corrected PKGBUILD and
installed (`makepkg` + `pacman -U`).

### Verification — the wall is gone

- nettle's own 32-bit testsuite on the rebuilt library: **All 116 tests
  passed** — every `ecc-*`, `ecdsa-*`, `eddsa-*`, `curve*` test. The ECC
  math is correct, not merely un-aborted.
- `repro/nettle-i386/ntls-handshake.c` (Wine-free) against the installed
  library: `HANDSHAKE OK` — P-256 and X25519. Was: abort.
- `wine-patches/repro-winhttp-adobe/httptest32.exe` against Adobe:
  `cc-api-data.adobe.io` → `HTTP 403`, `lcs-cops.adobe.io` → `HTTP 404`
  (real responses; TLS completes). Was: `WinHttpSendRequest err=12157`.

### Report destination

This is an **Arch packaging bug** — report at `bugs.archlinux.org` / the
`lib32-nettle` package on `gitlab.archlinux.org`. It is **not** a nettle
upstream bug (nettle removed the option deliberately and documented the
replacement) and **not** a Wine or Adobe bug. No prior filed report was
found for the exact signature. `repro/nettle-i386/` is the self-contained
Wine-free reproducer to attach.

### Outcome

The attempt-17 networking wall is **fixed at its real root cause** — a
stale flag in the Arch `lib32-nettle` PKGBUILD — with no Wine source
changed, nothing Adobe touched, and no faked value. The 32-bit ECC TLS
handshake works; `Set-up.exe`'s HTTPS requests now reach Adobe.

Attempt 17 delivered, end-to-end: the `mshtml` `FEATURE_BROWSER_EMULATION`
fix (React UI parses and runs) **and** the `lib32-nettle` fix (32-bit TLS
works). `scripts/install-cc-desktop.sh` stays WORK IN PROGRESS — the next
step is a full `Set-up.exe` run now that both walls are down.

## Full Set-up.exe run (2026-05-16, session 5)

Ran `Set-up.exe` end to end on the now-fixed system, with `+winhttp`,
`+wininet`, and `+server` traces and the installer's own logs
(`WAM.log`, dunamis).

### The networking wall is GONE

This is the headline. The installer's native workflow runs cleanly:
`ACQUIRE_LOCKS → CHECK_GENERAL_SYSTEM_REQUIREMENTS → CHECK_FOR_PROXY →
CHECK_FOR_NETWORK (NetworkState 1) → CHECK_ALREADY_INSTALLED_PRODUCT →
SHOW_WELCOME_SCREEN → START_SIGNIN_WORKFLOW`, and NGL's `GetSUSIURL`
**succeeds** — it fetches a real Sign-Up/Sign-In URL. The embedded
WebBrowser then fetches the entire Adobe sign-in module — the `darq/qr`
delegated-auth bundle (`index.js`, `DelegatedAuthRequest.js`,
`QRCodeRequest.js`, `PollingService.js`, `TokenRequest.js`, …), the
messaging client, polyfills — and hits `ims-na1.adobelogin.com`,
`delegated.identity.adobe.com` (×326), `lcs-cops.adobe.io`,
`resources.licenses.adobe.com`. **61× HTTP 200**, one 302. Attempt 17's
old `-1`/`HTTP_Status:0` wall is gone — the `lib32-nettle` + `mshtml`
fixes hold.

### The new wall — Wine `jscript`/`mshtml` cannot run the OOBE app

The embedded WebBrowser's React OOBE/sign-in app **renders its shell but
stalls on "Loading"** — it never shows the sign-in form. Its resources
all download (HTTP 200); the failure is at JavaScript *runtime* inside
Wine's IE-emulated engine. Trace evidence (`+winhttp,+wininet`, jscript
`warn`/`fixme` on by default):

- `mshtml:ActiveScriptSite_OnScriptError` — fires **twice**: the page's
  JS raised script errors.
- `jscript:exprval_call invoke undefined` ×4 — JS calling an undefined
  value as a function (a thrown `TypeError`).
- `jscript:JScriptProperty_SetProperty Unimplemented property
  70000001 / 70000002` — the app tries to configure the script engine
  (JS versioning); Wine `jscript` does not implement those properties.
- `mshtml:HTMLDOMImplementation2_createHTMLDocument (…)->((null) …)` —
  `document.implementation.createHTMLDocument()` returns null.
- `mshtml:HTMLWindow2_put_onerror … semi-stub` — the app's own
  `window.onerror` handler is not fully wired.

Wine's `mshtml` uses Wine-Gecko for the DOM but **Wine's own `jscript`
(an ES5-era engine) for `<script>` execution**. The modern Adobe OOBE /
delegated-auth app is past what `jscript` implements. The
`FEATURE_BROWSER_EMULATION` fix got the installer's *own* React bundle to
parse; the separate, newer sign-in app hits runtime gaps `jscript`
cannot satisfy.

### Downstream symptom — the restart loop

Because the OOBE UI never reaches "ready", the native bootstrapper's
watchdog times out after ~5 min: `CommBridge` "Number of retries to
connect inPipe exhausted with latest err = 536" + "Error initializing
OtherInstaller IPC", then a fresh `Workflow start`. Observed three full
cycles (`16:40 → 16:46 → 16:53`). Named-pipe *creation* works in Wine
(`create_named_pipe() = 0`); the IPC failure is the watchdog failing to
reach the hung UI process — a consequence, not the cause.

### Sub-finding — telemetry 400 (non-fatal, Wine bcrypt bug)

`dunamis` and the WAM `DunamisIngestHttpHandler` POST to
`cc-api-data.adobe.io/ingest` and get **HTTP 400** ("Error 1011: Missing
keys in the events array"). Cause: `bcrypt:BCryptExportKey` returns
`0xC0000023` (`STATUS_BUFFER_TOO_SMALL`) under Wine, so `dunamis` cannot
encrypt its events — they serialize empty, Adobe rejects the batch. This
is **analytics only**; Adobe tolerates telemetry failure and the
installer continues. Not pursued (a separate, minor Wine `bcrypt` bug).

### Classification — (a) Wine

- **(c) Adobe-side: ruled out.** Every substantive Adobe endpoint
  returned HTTP 200; sign-in resources, identity, licensing all served.
  The only 4xx is the non-fatal telemetry `/ingest` 400, itself caused
  by a Wine `bcrypt` bug — not an Adobe refusal of the install.
- **(b) host config: ruled out.** Wine-Gecko present, prefix builds,
  network/TLS verified.
- **(a) Wine: confirmed.** Wine's `jscript` engine cannot run the modern
  Adobe OOBE/sign-in React application to its ready state.

### Outcome — route reaches sign-in, blocked at the Wine jscript wall

`Set-up.exe` now gets all the way to the **sign-in step** — a genuine
advance: the networking wall that closed attempts 2 and 17 is gone. It
is blocked at a *new*, distinct wall: Wine's `jscript` engine is too old
for Adobe's modern OOBE app. Fixing that is open-ended Wine
engine-modernisation work (implementing modern JS runtime features in
`jscript.dll`), **not a fix that can be made or shipped in one session**
— and out of proportion to installing one app. It is a scoped Wine
follow-up.

No Adobe file was modified; no value was faked. `Set-up.exe` ran
completely unmodified. `scripts/install-cc-desktop.sh` stays WORK IN
PROGRESS — the installer route is honestly blocked at the Wine
`jscript` OOBE wall.
