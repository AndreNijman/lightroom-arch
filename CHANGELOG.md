# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-05-15

### Working — full photo editing

Adobe Lightroom (Creative Cloud desktop app, `Adobe Lightroom CC`
v9.3.1) is usable on Arch Linux under Wine. It launches, signs in,
authenticates against Adobe Creative Cloud, loads its full UI, browses
the local filesystem, opens and displays photos (loupe + Compare
views), and **edits them** — the develop sliders work and visibly
change the image. Launch with `./run-lightroom.sh`.

### Fixed

- **COM wrong-thread crash** (`lightroom.exe+0x28231C`,
  `RPC_E_WRONG_THREAD` → NULL deref) — every prior session crashed
  here. Fixed with a binary patch: a code-cave null-check routing the
  NULL case to LR's own error/unwind path
  (`scripts/patches/patch-lightroom-com-nullcheck.py`).
- **`SetThreadpoolTimerEx` abort after sign-in** — `AdobeGrowthSDK.dll`
  binary-patched to import `SetThreadpoolTimer` instead.
- **Media Foundation crash** — rebuilt `mf`/`mfplat`/`mfreadwrite`.

### Worked around

- **CameraRaw D3D12 crash** in `libvkd3d-1.dll` on opening a photo —
  GPU acceleration turned off in LR preferences
  (`gpu4setting="off"`); CameraRaw renders on the CPU.

### Known limitation

- GPU acceleration is off (Wine's D3D12→Vulkan `libvkd3d-1.dll` faults
  inside CameraRaw). Editing is CPU-rendered.

## [1.0.0] - 2026-05-15

### Working

Adobe Lightroom (Creative Cloud desktop app, `Adobe Lightroom CC`
v9.3.1) runs on Arch Linux under Wine. It launches, renders its full
UI, runs a stable render loop, connects to Adobe over TLS, and presents
an interactive Adobe sign-in page. Sign in with a Creative Cloud
account to activate. Launch with `./run-lightroom.sh`.

### The stack

- PhialsBasement patched Wine 10.0 (bundled binary)
- Patched `d2d1.dll`: `D2D1ColorManagement` effect registered +
  `dwrite`/`xmllite`/`ole32` changed from delay-imports to normal imports
- Wine builtin dwrite (`dwrite=b`)
- WineD3D, not DXVK (`d3d11=b;dxgi=b;d3d10core=b;d3d9=b`)
- Microsoft Edge WebView2 runtime copied into the prefix
- `UseXVidMode=N` for Hyprland/XWayland

### Blockers solved

- Direct2D init failure (`HResult 0x88990028`) — `d2d1` ColorManagement
  effect patch.
- dwrite "delay-load" crash — real cause was d2d1's delay-load helper;
  fixed with non-delay imports.
- `lightroom.exe+0x28231C` null-pointer crash — DXVK-specific; fixed by
  using WineD3D.
- Missing WebView2 runtime — installed into the prefix.

### Dead end

- Rebuilding Wine from source WoW64-style (`--enable-archs`) produced a
  systemically broken Wine. Reverted to the bundled Wine.

## [0.1.0] - 2026-04-28

### What this release is

Failure documentation. Modern Adobe Lightroom (cloud and Classic CC) cannot be installed on Arch Linux via Wine as of April 2026.

### Approaches tested and abandoned

- Lutris (Lightroom 6.14 target) - blocked by Adobe ending LR 6.14 distribution.
- Wine vanilla + winetricks (Lightroom cloud) - blocked at MSHTML; verb removed from winetricks.
- Bottles caffe runtime + browser deps (Lightroom cloud) - bootstrapper aborts at wininet/iertutil.
- Bottles soda runtime + default deps (Lightroom cloud) - .NET COM registration failure.

### Upstream blockers

- Adobe ended Lightroom 6.14 download distribution on 2023-12-31.
- winetricks 20260125 removed the mshtml verb.
- IE/iertutil/COM stack is no longer functional on modern Wine, blocking the Adobe CC bootstrapper.

### What does work on Arch

- darktable, RawTherapee, digiKam - all native, all maintained, all handle NEF.
