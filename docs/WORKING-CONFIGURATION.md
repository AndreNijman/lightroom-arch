# Working Configuration — Adobe Lightroom on Arch Linux via Wine

After nine attempts, Adobe Lightroom (Creative Cloud desktop app) is
usable under Wine on Arch Linux (Hyprland/Wayland). It launches, signs
in, loads its full UI, browses photos, and edits them. Run it with
`./run-lightroom.sh`.

## Status

**Working:** LR launches, signs in and activates against Adobe
Creative Cloud, renders its complete interface, browses the local
filesystem, opens and displays photos (loupe + Compare views), opens
the Presets and Edit panels, and edits photos — the develop sliders
work and visibly change the image.

**Requires the user:** sign in with an Adobe Creative Cloud account on
first launch (WebView2 sign-in page).

**Known limitation:** GPU acceleration is off — Wine's D3D12→Vulkan
layer (`libvkd3d-1.dll`) faults inside CameraRaw's GPU pipeline.
Editing is CPU-rendered (slower, but fully functional).

## The stack

| Layer | Choice | Why |
|-------|--------|-----|
| Wine | PhialsBasement patched Wine 10.0 (bundled binary) | MSHTML/MSXML patches for Adobe; building Wine from source WoW64-style produced a systemically broken Wine — do not |
| `lightroom.exe` | Binary-patched at `+0x28231C` | COM `RPC_E_WRONG_THREAD` → NULL deref; code-cave null-check (`scripts/patches/patch-lightroom-com-nullcheck.py`) |
| `AdobeGrowthSDK.dll` | Binary-patched import | `SetThreadpoolTimerEx` (unexported) → `SetThreadpoolTimer` |
| d2d1.dll | Patched (see below) | Wine's stock d2d1 lacks the ColorManagement effect and its delay-load helper crashes |
| dwrite | Wine builtin (`dwrite=b`) | Native Windows DWrite.dll infinite-recurses under Wine |
| Direct3D 9/10/11 | WineD3D (`d3d11=b;dxgi=b;d3d10core=b;d3d9=b`) | DXVK caused a null-pointer crash at `lightroom.exe+0x28231C` |
| Direct3D 12 | vkd3d-proton copied into prefix (`d3d12=n;d3d12core=n`) | bundled d3d12core pulled the crashing standalone `libvkd3d-1` |
| Media Foundation | Rebuilt `mf`/`mfplat`/`mfreadwrite` | Wine builtin MF null-derefs on `E_NOINTERFACE` |
| GPU acceleration | **off** — `gpu4setting="off"` in `Lightroom CC Preferences.agprefs` | CameraRaw's D3D12 path crashes in `libvkd3d-1.dll`; CPU rendering is stable |
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

## The journey (attempts 1-9)

1-3. Adobe CC installer under Wine — blue-screen CEF render failures.
4. Patched d2d1 ColorManagement effect — got past the first D2D wall,
   hit a dwrite "delay-load" crash.
5. Full Wine rebuild attempt — WoW64 single-tree build produced a
   broken Wine. Dead end; reverted.
6. Diagnosed the real bug via `minidump_stackwalk`: d2d1's delay-load
   helper, not dwrite. Fixed with non-delay imports. Then: native
   dwrite recursion → builtin dwrite; DXVK crash → WineD3D; WebView2
   missing → installed runtime. UI renders.
7. Sign-in: `SetThreadpoolTimerEx` abort → `AdobeGrowthSDK.dll` import
   patch. Media Foundation crash → rebuilt `mf` DLLs.
8. COM `RPC_E_WRONG_THREAD` crash at `lightroom.exe+0x28231C` → binary
   code-cave null-check patch. LR runs stable; browses photos.
9. Opening a photo crashed in `libvkd3d-1.dll` (CameraRaw's D3D12 path)
   → GPU acceleration turned off in LR preferences. Photo editing
   works on the CPU.

See `docs/attempt-7-*`, `attempt-8-*`, `attempt-9-*` for detail.

## Reproduce

```bash
./run-lightroom.sh
```

Sign in with an Adobe Creative Cloud account on first launch. To
close LR: `WINEPREFIX=$HOME/.wine_adobe ~/opt/wine-adobe/files/bin/wineserver -k9`.
