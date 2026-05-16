# WebBrowser Control Repro — Feature Browser Emulation

## Purpose

This directory contains a minimal Win32 C program (`wbhost.exe`) that embeds an IE WebBrowser control, used to reproduce Wine's `FEATURE_BROWSER_EMULATION` registry handling for mshtml.dll.

## How It Works

`wbhost.exe` is a console application that:
1. Creates a top-level window (offscreen, not visible).
2. Instantiates the WebBrowser ActiveX control (IWebBrowser2).
3. Provides a minimal client site implementing `IOleClientSite`, `IOleInPlaceSite`, and `IOleInPlaceFrame`.
4. Activates the control in-place via `DoVerb(OLEIVERB_INPLACEACTIVATE)`.
5. Navigates to a `file://` URL of an HTML file (passed as argv[1]).
6. Pumps the message loop and polls `ReadyState` until the document is fully loaded (or timeout after 15 seconds).
7. Reads the document title via `IHTMLDocument2::get_title()` and prints it to stdout as `TITLE=<value>`.
8. Exits cleanly with return code 0.

## Test Case: `test.html`

The test HTML file demonstrates ECMAScript compatibility:

```html
<!DOCTYPE html>
<html><head>
<meta http-equiv="X-UA-Compatible" content="chrome=1">
<title>NOSCRIPT</title>
</head><body>
<script type="text/javascript">document.title="ES5-RAN";</script>
<script type="text/javascript">
let v=1; const dbl=x=>x*2; class K{ m(){ return `tok${dbl(v)}`; } }
document.title = (new K().m()==="tok2") ? "ES6-OK" : "ES6-BAD";
</script>
</body></html>
```

## Expected Behavior Under Wine

**Default (unpatched Wine):**
- Process name is `wbhost.exe`, not `iexplore.exe`.
- mshtml defaults to **IE7 compatibility mode** based on doctype.
- The second `<script>` block contains ES6 syntax (`let`, `const`, arrow functions, template literals, class).
- JScript 7 (IE7 engine) does not support ES6, so the second script is a **SyntaxError**.
- First script runs successfully, setting title to `"ES5-RAN"`.
- Second script fails; title remains `"ES5-RAN"`.
- Output: `TITLE=ES5-RAN`

**With FEATURE_BROWSER_EMULATION Registry Patch (patched Wine):**
- Setting `HKCU\Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION` value `wbhost.exe` = DWORD `0x2af9` (11001, IE11) opts the process into **IE11 mode**.
- IE11 supports ES6 syntax (via modern JScript engine or Chakra).
- Both scripts run successfully.
- Second script evaluates the ES6 class and sets title to `"ES6-OK"`.
- Output: `TITLE=ES6-OK`

Stock Wine ignores this registry key; a patched Wine honours it and uses it to select the mshtml compatibility level.

## Building

```bash
cd /home/andre/Projects/lightroom-arch/wine-patches/repro-feature-browser-emulation/
make
```

This produces `wbhost.exe` (32-bit Windows PE) compiled with `i686-w64-mingw32-gcc`.

## Running (Under Wine, not on this system)

```bash
wine wbhost.exe /path/to/test.html
```

Output will be:
- **Default Wine:** `TITLE=ES5-RAN`
- **With registry patch active:** `TITLE=ES6-OK`

## Files

- `wbhost.c` — The WebBrowser host program (console, single-file, ANSI C, mingw-compatible).
- `Makefile` — Build rules.
- `test.html` — Test case demonstrating ES5 vs ES6 compatibility.
- `README.md` — This file.
