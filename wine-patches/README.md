# Wine patches

The prebuilt `winex11.so` and `uiautomationcore.dll` carry three fixes
(attempts 12–15, see `docs/`). `run-lightroom.sh` installs both on launch,
backing up each stock file as `<name>.orig`.

| Patch | File | Fixes |
|-------|------|-------|
| `winex11-vulkan-child-flush-fix.patch` | `winex11.so` | GPU-on Develop-edit flicker |
| `winex11-wm-close-fix.patch` | `winex11.so` | Hyprland close shortcut a no-op |
| `uiautomationcore-disconnect-all-providers.patch` | `uiautomationcore.dll` | Lightroom stalls on exit |

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

### Rebuilding

`uiautomationcore.dll` is a PE DLL; build it from the same configured tree:

```sh
git apply /path/to/uiautomationcore-disconnect-all-providers.patch
make -j"$(nproc)" dlls/uiautomationcore/x86_64-windows/uiautomationcore.dll
# copy it over wine-patches/uiautomationcore.dll
```
