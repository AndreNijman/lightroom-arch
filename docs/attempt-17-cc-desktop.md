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

### Upstream status

No filed report found for this exact signature (`_nettle_ecc_mod_random`
`nbytes` assertion on `i386`) — searched the Wine GitLab/Bugzilla, the
`nettle` tracker, and `bugs.archlinux.org`. The *class* of bug — a
`lib32-nettle`/`lib32-gnutls` update breaking 32-bit TLS — is recurring on
Arch (e.g. historical FS#44828). **This belongs upstream in `nettle`**
(report to the `nettle-bugs` list / `gitlab.com/gnutls/nettle`) and/or as
an Arch `lib32-nettle` packaging bug — **not** in Wine and **not** in
Adobe. `repro/nettle-i386/ntls-handshake.c` is the self-contained,
Wine-free reproducer to attach.

### Outcome — Step 5 closed

The networking wall is **not a Wine bug and not an Adobe rejection**. It
is a broken 32-bit crypto library (`nettle` 4.0 on `i386`) on this host.
Consequences:

- **There is nothing for Wine to patch.** The `wine-patches/` pattern
  (source patch + prebuilt DLL) does not apply — `secur32`/`winhttp` are
  faithful passthroughs to a `nettle` that is itself broken on `i386`.
  The earlier "scoped follow-up: build i386-unix Wine, patch `schannel`"
  plan is **void** — it would have patched innocent code.
- The Adobe CC installer route stays **blocked at the networking wall**
  until the host's 32-bit `nettle` is fixed: upstream `nettle`/Arch ship a
  corrected `lib32-nettle`, or the user downgrades `lib32-nettle` to a
  3.x release that passes `repro/nettle-i386/ntls-handshake.c` 32-bit.
  Either is a host/distro action, outside this repo's scope.
- `scripts/install-cc-desktop.sh` stays WORK IN PROGRESS.

What attempt 17 *did* deliver end-to-end: the `mshtml`
`FEATURE_BROWSER_EMULATION` fix (the installer's React UI now parses and
runs, Adobe binaries unmodified). The networking wall is a separate,
host-environment blocker — no longer a Wine task.
