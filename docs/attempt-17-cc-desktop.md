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

## Remaining walls (post-parse)

With JS running, two issues remain before the installer is usable:

1. **Rendered DOM does not paint** — the host window shows only its teal
   background though React built the DOM. `ieframe:ViewObject_Draw` is a
   Wine stub (fixme); the embedded WebBrowser ActiveX `IViewObject::Draw`
   does nothing. Prime suspect for the blank paint.
2. **Platform mis-detection** — the React app tags its root `cci-root
   mac` and renders a `spectrum-CircleLoader` spinner; it sniffs the UA
   for `\bMSIE\b` / `\bTrident\b` and `isWinPlatform`. Wine's IE11-mode
   user-agent lacks `MSIE`, so the installer may think it is on macOS
   (`cci.error.product.platformIneligible.macarm64`).

(continued — see commits / changelog)
