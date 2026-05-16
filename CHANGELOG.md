# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### In progress — installer-driven Creative Cloud (no rsync)

- Working toward a one-command, rsync-free install: anyone who clones the
  repo runs `scripts/install-cc-desktop.sh` and the Adobe Creative Cloud
  Desktop installer runs under Wine — no Windows partition, no copying an
  existing install.
- **Corrected attempt 2's diagnosis.** The blank teal CC installer window
  is *not* a TLS failure. The Adobe analytics POST completes its TLS
  handshake; the installer's UI assets are extracted locally, not
  downloaded. (`docs/attempt-17-cc-desktop.md`)
- **Root-caused the blank installer.** `Set-up.exe`'s UI is a modern
  (ES6+) React/webpack bundle hosted in Wine's `mshtml` WebBrowser
  control. Wine's `mshtml` runs JavaScript through `jscript.dll` (an
  ES5-era engine), not Gecko's SpiderMonkey. `index.html` carries
  `<meta http-equiv='X-UA-Compatible' content='chrome=1'>`; Wine cannot
  parse `chrome=1`, drops to IE7 compat mode, and `jscript` rejects the
  ES6 syntax with `SyntaxError 800a03ea` — React never mounts.
- **Cleared the JS parse wall.** Rewriting that meta to `content='IE=11'`
  puts Wine `mshtml` in IE11 compat mode; `jscript` runs in ES6 mode and
  the bundle parses with zero syntax errors — React mounts and React
  Spectrum initialises. `scripts/install-cc-desktop.sh` performs this
  rewrite automatically via an `inotifywait` watcher on the installer's
  temp directory.
- **Known remaining wall:** the React installer runs but stays in its
  loading state (platform mis-detection / catalog fetch), so the native
  teal splash never lifts to reveal the WebBrowser. Multi-session work;
  tracked in `docs/attempt-17-cc-desktop.md`.

## [2.4.0] - 2026-05-16

### Fixed — UI shapes render correctly (Direct2D arc fix)

- **Buttons, circles and rounded panels no longer render malformed.**
  Lightroom drew pill-shaped toolbar buttons as pointed hexagons, the
  rating circle as a jagged polygon, icon badges as diamonds, and rounded
  panels with cut corners.
- **Root cause** (`docs/attempt-16`): Lightroom draws its whole UI with
  Direct2D and uses `ID2D1GeometrySink::AddArc` for every rounded shape
  (traced: 214 `AddArc` calls). Stock Wine's `AddArc` is an unimplemented
  stub — it discards the arc and inserts a straight line to the arc
  endpoint, so every curve collapsed to a chord.
- **Fix** (`installers/wine-patches/wine-d2d1-addarc.patch`): implements
  `AddArc` — converts the arc (SVG endpoint parameterisation) to quadratic
  Béziers and feeds the sink's existing curve path. Verified: pill buttons,
  the rating circle, the "Assisted Culling" badge and rounded panels all
  render with proper curves.
- The patched `d2d1.dll` ships in `wine-patches/` and `run-lightroom.sh`
  installs it idempotently (stock kept as `d2d1.dll.orig`). It carries all
  three d2d1 fixes: the ColorManagement effect, non-delay imports, and
  `AddArc`.

## [2.3.0] - 2026-05-16

### Fixed — Lightroom now exits cleanly

Lightroom ran fine but would not *quit* properly. Two fixes, both Wine
patches (`docs/attempt-15`):

- **Hyprland close shortcut did nothing.** Lightroom runs in a Wine
  virtual desktop; `killactive` sends `WM_DELETE_WINDOW` to the desktop
  window, which stock `winex11` turns into a session logoff
  (`ExitWindows`). Lightroom vetoes the logoff, so the shortcut was a
  total no-op. `winex11-wm-close-fix.patch` routes a virtual-desktop
  close request to the focused application window instead (Alt+F4
  semantics) — the same direct close the titlebar button uses.
- **Shutdown aborted on `UiaDisconnectAllProviders`.** Lightroom calls
  it during shutdown; stock Wine's `uiautomationcore` never exported the
  function, so the call hit an unimplemented-stub abort and Lightroom
  failed to terminate reliably. `uiautomationcore-disconnect-all-providers.patch`
  exports it as a no-op returning `S_OK`.
- `run-lightroom.sh` installs the patched `uiautomationcore.dll`
  (idempotent; keeps the stock DLL as `uiautomationcore.dll.orig`) and
  has a `trap` that runs `scripts/kill-wine.sh` on exit, draining the
  `explorer.exe` desktop host and helper processes left after
  `lightroom.exe` quits.
- Verified both close paths: `Super+Q` and the titlebar close button
  each end with 0 Wine processes, 0 windows, no abort.

The patched `winex11.so` now carries both the attempt-14 flicker fix and
the attempt-15 close fix.

## [2.2.0] - 2026-05-15

### Fixed — GPU-on develop-edit flicker (the real fix)

- **GPU acceleration is back on, flicker-free.** The 2.1.0 release
  worked around the develop-edit flicker by disabling Lightroom's GPU
  acceleration. This release fixes the bug at its source.
- **Root cause** (`docs/attempt-12`): not in `dxgi`/`d3d12` — traces
  show clean presents, no swapchain recreation. It is in Wine's
  `winex11`. CameraRaw's Develop preview is a D3D12 swapchain on a child
  window; `winex11` composites that child offscreen and `StretchBlt`s it
  onto the parent X drawable every present, while the parent
  window-surface flush repaints the *same* drawable — the two race and
  the preview flashes against Lightroom's grey canvas during a drag.
- **Fix** (`docs/attempt-14`, `wine-patches/`): `winex11` now tracks the
  rects of offscreen Vulkan child surfaces and excludes them from the
  parent window-surface flush, so a parent UI repaint no longer
  overpaints the preview. The per-present `StretchBlt` is left as the
  sole writer of that region. Patch confined to `dlls/winex11.drv/`,
  no ABI change. Verified: **0 blank frames across 700+ captured frames**
  of GPU-on slider editing (was ~65/293).
- `run-lightroom.sh` installs the patched `winex11.so` on launch
  (idempotent; keeps the stock driver as `winex11.so.orig`). Lightroom's
  GPU acceleration is re-enabled in the prefix preferences.
- An intermediate `needs_offscreen_rendering()` patch (`docs/attempt-13`)
  was tried first and proved a no-op — kept documented for the record.

## [2.1.0] - 2026-05-15

### Fixed — display quality

- **Pixelly / aliased UI** — the Wine virtual desktop was a fixed
  1280x800 framebuffer bitmap-upscaled 1.5x into the 1920x1200 host
  window. `run-lightroom.sh` now sizes the virtual desktop to the
  active monitor and fullscreens its window, so the framebuffer maps
  1:1 to physical pixels and the UI is crisp.
- **Develop-edit flashing** — while editing, the preview flashed
  between the image and an empty canvas. CameraRaw renders the Develop
  preview with Direct3D 12; Wine's D3D12 present path blanks between
  renders. Disabling Lightroom's GPU acceleration (CPU rendering) fixes
  it — verified flicker-free across 435 frames of aggressive editing,
  versus constant flashing with the GPU on. This supersedes 2.0.0's
  "GPU acceleration is on" claim.

### Fixed — process hygiene

- `wineserver -k9` left orphaned `explorer.exe` helpers alive (55 had
  accumulated over one session), each owning a zombie virtual-desktop
  window. `scripts/kill-wine.sh` kills every process whose executable
  resolves into the bundled Wine install; `run-lightroom.sh` uses it.

### Changed

- GPU acceleration is **off** (`gpu4setting="off"`). Develop edits
  render on the CPU — slightly slower, but with no flashing.

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

### CameraRaw D3D12 crash — resolved (was a misconfiguration)

- Opening a photo crashed in `libvkd3d-1.dll` via CameraRaw → `dxgi` →
  D3D12. Investigation (attempt 10) found this was **not** an upstream
  Wine bug: a vkd3d-proton `d3d12core.dll` had been dropped into the
  prefix, mixing it with Wine's builtin `dxgi.dll` — incompatible D3D12
  implementations. With the whole D3D12 stack kept builtin
  (`d3d12=b;d3d12core=b`), GPU acceleration works and there is no
  crash. GPU acceleration is **on**.

### No known limitations

- GPU acceleration works (Wine builtin D3D12 → Vulkan, RADV on the
  AMD Radeon 780M).

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
