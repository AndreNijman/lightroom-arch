# Working Configuration — Adobe Lightroom on Arch Linux via Wine

After six attempts, Adobe Lightroom runs under Wine on Arch Linux
(Hyprland/Wayland). The application boots, renders its full UI, and
presents a working Adobe sign-in page. Run it with `./run-lightroom.sh`.

## Status

**Working:** LR launches, renders its complete interface (menus,
panels, toolbar, edit tools), runs a stable render loop, connects to
Adobe servers over TLS, and shows an interactive WebView2/Chromium
sign-in page.

**Requires the user:** sign in with an Adobe Creative Cloud account to
activate. The installed package is cloud Lightroom, which needs Adobe
account sign-in to proceed past the sign-in screen.

## The stack

| Layer | Choice | Why |
|-------|--------|-----|
| Wine | PhialsBasement patched Wine 10.0 (bundled binary) | MSHTML/MSXML patches for Adobe; building Wine from source WoW64-style produced a systemically broken Wine — do not |
| d2d1.dll | Patched (see below) | Wine's stock d2d1 lacks the ColorManagement effect and its delay-load helper crashes |
| dwrite | Wine builtin (`dwrite=b`) | Native Windows DWrite.dll infinite-recurses under Wine |
| Direct3D | WineD3D (`d3d11=b;dxgi=b;d3d10core=b;d3d9=b`) | DXVK caused a null-pointer crash at `lightroom.exe+0x28231C` |
| WebView2 | Edge WebView2 runtime copied into prefix | LR's account/sign-in UI requires it |
| X11 | `UseXVidMode=N` in `user.reg` | XVidMode assertion crash on Hyprland/XWayland |

## The d2d1.dll patch

Two changes to Wine's `dlls/d2d1`, rebuilt and installed into
`~/opt/wine-adobe/files/lib/wine/x86_64-windows/d2d1.dll` and the
prefix's `system32`:

1. **`effect.c`** — register `CLSID_D2D1ColorManagement` as a builtin
   stub effect. Without it LR's D2D init fails with
   `CreateD2DDeviceResources HResult 0x88990028`.
   Patch: `installers/wine-patches/wine-d2d1-color-management.patch`

2. **`Makefile.in`** — move `dwrite xmllite ole32` from `DELAYIMPORTS`
   to `IMPORTS`. The delay-load helper in a mingw-16.1.0-built d2d1.dll
   writes the resolved IAT entry past the end of the image and faults
   in the bundled Wine loader. Normal imports skip the helper entirely.
   Patch: `installers/wine-patches/wine-d2d1-nondelay-imports.patch`

## The journey (attempts 1-6)

1-3. Adobe CC installer under Wine — blue-screen CEF render failures.
4. Patched d2d1 ColorManagement effect — got past the first D2D wall,
   hit a dwrite "delay-load" crash.
5. Full Wine rebuild attempt — WoW64 single-tree build produced a
   broken Wine. Dead end; reverted.
6. Diagnosed the real bug via `minidump_stackwalk`: d2d1's delay-load
   helper, not dwrite. Fixed with non-delay imports. Then: native
   dwrite recursion → builtin dwrite; DXVK crash → WineD3D; WebView2
   missing → installed runtime. LR now runs.

## Reproduce

```bash
./run-lightroom.sh
```

Then sign in with an Adobe Creative Cloud account in the WebView2
sign-in page.
