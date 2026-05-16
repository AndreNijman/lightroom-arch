# Wine patches

The prebuilt `winex11.so` and `uiautomationcore.dll` carry three fixes
(attempts 12–15, see `docs/`). `run-lightroom.sh` installs both on launch,
backing up each stock file as `<name>.orig`.

| Patch | File | Fixes |
|-------|------|-------|
| `winex11-vulkan-child-flush-fix.patch` | `winex11.so` | GPU-on Develop-edit flicker |
| `winex11-wm-close-fix.patch` | `winex11.so` | Hyprland close shortcut a no-op |
| `uiautomationcore-disconnect-all-providers.patch` | `uiautomationcore.dll` | Lightroom stalls on exit |
| `../installers/wine-patches/wine-d2d1-addarc.patch` | `d2d1.dll` | rounded UI shapes render as polygons |
| `mshtml-feature-browser-emulation.patch` | `mshtml-i386.dll`, `mshtml-x86_64.dll` | CC installer's ES6 React bundle is a `jscript` SyntaxError (mshtml ignores `FEATURE_BROWSER_EMULATION`, defaults to IE7) |

## winex11 — D3D child-swapchain flicker fix

`winex11-vulkan-child-flush-fix.patch` + the prebuilt `winex11.so` fix the
GPU-on Develop-edit flicker (attempts 12–14, see `docs/`).

### The bug

Adobe CameraRaw renders the Develop preview into a Direct3D 12 swapchain on
a **child window**. Wine's `winex11` driver composites a D3D child window
"offscreen": it keeps the rendered frame in a redirected X window and, on
every present, `StretchBlt`s it onto the parent's X drawable
(`X11DRV_vulkan_surface_presented`). But the parent window-surface flush
(`x11drv_surface_flush`) repaints that *same* drawable — and during a
slider drag Lightroom repaints its UI continuously. The parent flush
overpaints the preview between presents → the preview flashes between the
image and Lightroom's grey canvas.

### The fix

`winex11` now tracks the rects of offscreen Vulkan child surfaces
(`offscreen_vk_*` in `vulkan.c`). `x11drv_surface_flush` excludes those
rects from the parent's `XPutImage`/`XShmPutImage`, so a parent UI repaint
no longer overpaints the child. The per-present `StretchBlt` becomes the
sole writer of the preview region — no race, no flicker. Verified: 0 blank
frames across 880+ captured frames of GPU-on slider editing (was ~65/293).

The patch touches only `dlls/winex11.drv/` (`vulkan.c`, `bitblt.c`,
`x11drv.h`) — no ABI change, no behaviour change for any window that is
not an offscreen Vulkan child.

### The prebuilt binary

`winex11.so` is the 64-bit Unix driver built from Proton Wine commit
`dbb32ff8` (branch `experimental_10.0` of ValveSoftware/wine) — the exact
commit the bundled `~/opt/wine-adobe` build was made from — with the patch
applied. `run-lightroom.sh` installs it into the bundle on launch (backing
up the stock driver as `winex11.so.orig`).

### Rebuilding (if the bundled Wine is updated)

```sh
git clone https://github.com/ValveSoftware/wine.git
cd wine && git checkout <commit matching ~/opt/wine-adobe/version>
git apply /path/to/winex11-vulkan-child-flush-fix.patch
./autogen.sh && mkdir build && cd build
../configure --enable-archs=x86_64 --disable-tests
make -j"$(nproc)" dlls/winex11.drv/winex11.so
strip dlls/winex11.drv/winex11.so   # optional
# copy dlls/winex11.drv/winex11.so over wine-patches/winex11.so
```

The driver ABI is fixed per Wine commit, so the rebuilt `winex11.so` must
come from the commit the bundled build uses (`~/opt/wine-adobe/version`).
The same rebuild produces the close-fix `winex11.so` — both patches touch
only `dlls/winex11.drv/`, so apply both before `make`.

## winex11 — window-manager close fix

`winex11-wm-close-fix.patch` (also baked into the prebuilt `winex11.so`).

### The bug

Lightroom runs inside a Wine *virtual desktop*. A window-manager close
request (Hyprland's `killactive`, bound to the close shortcut) lands on the
desktop window. Stock `winex11` (`handle_wm_protocols` in `event.c`) turns
that into `SC_CLOSE` on the desktop window, whose proc calls `ExitWindows()`
— a session logoff that broadcasts `WM_QUERYENDSESSION`. Lightroom vetoes /
stalls that broadcast, so the logoff is cancelled and the close shortcut
does nothing at all.

### The fix

In a virtual desktop, `handle_wm_protocols` now routes a `WM_DELETE_WINDOW`
on the desktop to `SC_CLOSE` on the *focused application window* (Alt+F4
semantics) instead of the desktop. That closes Lightroom directly, the same
path its own titlebar close button uses — no vetoable logoff.

## uiautomationcore — UiaDisconnectAllProviders

`uiautomationcore-disconnect-all-providers.patch` + the prebuilt
`uiautomationcore.dll`.

### The bug

During shutdown Lightroom calls `UiaDisconnectAllProviders()`. Stock Wine's
`uiautomationcore` never exported it (the spec line was commented out), so
the call resolved to an unimplemented stub and Wine aborted — Lightroom
failed to terminate cleanly. With the winex11 close fix in place this was
the next wall: the close shortcut and titlebar button reached shutdown but
stalled here.

### The fix

`uiautomationcore` now exports `UiaDisconnectAllProviders` as a no-op that
returns `S_OK` (`uia_provider.c`, `.spec`, header). Per-process UI
Automation provider state is torn down at process exit anyway, so doing
nothing is safe and lets Lightroom's shutdown finish.

## d2d1 — UI shape rendering (AddArc)

The prebuilt `d2d1.dll` here carries three patches (sources in
`../installers/wine-patches/`): `wine-d2d1-color-management.patch` and
`wine-d2d1-nondelay-imports.patch` (attempts 4 and 6) plus
`wine-d2d1-addarc.patch` (attempt 16).

### The bug

Lightroom draws its UI with Direct2D and uses
`ID2D1GeometrySink::AddArc` for every rounded shape (traced: 214 calls).
Stock Wine's `AddArc` is an unimplemented stub — it discards the arc and
inserts a single straight line to the arc's endpoint. So pill buttons
rendered as pointed hexagons, circles as polygons, rounded panels with
cut corners.

### The fix

`wine-d2d1-addarc.patch` implements `AddArc` in `dlls/d2d1/geometry.c`:
it converts the arc (SVG endpoint parameterisation → centre form),
splits the sweep into ≤30° pieces, approximates each with a quadratic
Bézier, and feeds the sink's existing `AddQuadraticBeziers` path. A
genuine upstream Wine bug — the patch is self-contained and upstreamable.

### Rebuilding

```sh
git apply wine-d2d1-color-management.patch wine-d2d1-nondelay-imports.patch wine-d2d1-addarc.patch
make -j"$(nproc)" dlls/d2d1/x86_64-windows/d2d1.dll
# copy it over wine-patches/d2d1.dll
```

### Rebuilding

`uiautomationcore.dll` is a PE DLL; build it from the same configured tree:

```sh
git apply /path/to/uiautomationcore-disconnect-all-providers.patch
make -j"$(nproc)" dlls/uiautomationcore/x86_64-windows/uiautomationcore.dll
# copy it over wine-patches/uiautomationcore.dll
```

## mshtml — FEATURE_BROWSER_EMULATION (CC installer ES6 bundle)

`mshtml-feature-browser-emulation.patch` + the prebuilt `mshtml-i386.dll`
and `mshtml-x86_64.dll`.

### The bug

The Adobe Creative Cloud Desktop installer (`Set-up.exe`) is a
`urlmon`/`ieframe` host: its UI is a modern (`let`/`const`) React/webpack
bundle rendered in an embedded IE **WebBrowser control**, i.e. Wine's
`mshtml`. `mshtml` runs JavaScript through `jscript.dll`, whose accepted
language depends on the document's *compat mode*.

`Set-up.exe` is not `iexplore.exe`, so Wine's `mshtml` doctype handler
(`dlls/mshtml/mutation.c`) defaults its document to **IE7** compat mode.
In IE7 mode `jscript` rejects `let`/`const` — the React bundle dies with
`SyntaxError 800a03ea`, React never mounts, the installer paints only its
teal splash.

On real Windows this works because `Set-up.exe` opts itself into IE11 by
writing the standard **`FEATURE_BROWSER_EMULATION`** registry value for
its own executable (`HKCU\…\Internet Explorer\Main\FeatureControl\
FEATURE_BROWSER_EMULATION` → `"Set-up.exe"=dword:00002af9`, 11001 = IE11).
Windows IE honours that key for embedded WebBrowser controls. **Wine's
`mshtml` reads `FEATURE_BROWSER_EMULATION` nowhere** — the key is ignored,
so the installer stays stuck at IE7.

The `chrome=1` in `index.html`'s `<meta http-equiv='X-UA-Compatible'>` is
a red herring: `parse_ua_compatible()` returns `COMPAT_MODE_INVALID` for
any non-`IE=` token, so the meta is a no-op — it never forces IE7, and a
page with no meta at all lands in IE7 the same way.

### The fix

The patch adds `get_feature_browser_emulation()` to `mutation.c`: it reads
the `FEATURE_BROWSER_EMULATION` DWORD for the current process executable
(HKCU then HKLM) and maps it to a compat mode (7000→IE7 … 11000/11001→
IE11). The doctype handler consults it *before* the `iexplore` heuristic —
an explicit per-exe opt-in wins. If the key is absent, behaviour is byte
-for-byte unchanged (still IE7 for a non-`iexplore` host).

This is the documented Windows mechanism, so Adobe's installer runs
**completely unmodified** — no `index.html` rewrite, no registry
pre-seeding (`Set-up.exe` writes the key itself). Result: `Set-up.exe`'s
WebBrowser runs in IE11, the React bundle parses with zero `jscript`
syntax errors. Genuine upstream Wine gap — self-contained, upstreamable.

### Repro

`repro-feature-browser-emulation/` is a minimal, non-Adobe repro: a tiny
WebBrowser-control host (`wbhost.c` → `wbhost.exe`) navigates to
`test.html` (`<!DOCTYPE html>` + a `let`/`const` snippet) and prints the
resulting `document.title`.

| `mshtml` | `FEATURE_BROWSER_EMULATION\wbhost.exe` | Output |
|----------|----------------------------------------|--------|
| stock    | `0x2af9` set        | `TITLE=ES5-RAN` (key ignored → IE7) |
| patched  | `0x2af9` set        | `TITLE=ES6-OK` (→ IE11) |
| patched  | absent              | `TITLE=ES5-RAN` (unchanged IE7 default) |

### Rebuilding

```sh
git apply /path/to/mshtml-feature-browser-emulation.patch
make -j"$(nproc)" dlls/mshtml/i386-windows/mshtml.dll \
                  dlls/mshtml/x86_64-windows/mshtml.dll
i686-w64-mingw32-strip   dlls/mshtml/i386-windows/mshtml.dll
x86_64-w64-mingw32-strip dlls/mshtml/x86_64-windows/mshtml.dll
# copy to wine-patches/mshtml-i386.dll and wine-patches/mshtml-x86_64.dll
```

`Set-up.exe` is a 32-bit PE, so `mshtml-i386.dll` is the one that matters
for the installer; `mshtml-x86_64.dll` is shipped for 64-bit hosts.
