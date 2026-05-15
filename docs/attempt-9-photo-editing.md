# Attempt 9: Opening and Editing Photos — the D3D12/vkd3d Crash

## Where attempt 8 left off

The COM null-check patch made LR stable: full UI, browses the
filesystem, displays a thumbnail grid. Pushing further — opening a
photo into the loupe / edit view — revealed the next wall.

## The crash

Opening a photo for editing crashed a worker thread:

```
EXCEPTION_ACCESS_VIOLATION_READ  addr=0x0
 0  libvkd3d-1.dll + 0x3c5d0     (rax=0, rcx=0 — null deref)
 1  dxgi.dll + 0x6d9a
 2  d3d12core.dll + 0x3c8777
 ...
 9  CameraRaw.dll + 0x18fc335
10  CameraRaw.dll + ...
```

`CameraRaw.dll` — LR's raw/develop engine — uses **Direct3D 12** for
GPU-accelerated image processing. The chain is
CameraRaw → `dxgi.dll` → `d3d12core.dll` → `libvkd3d-1.dll`, and
`libvkd3d-1.dll` (Wine's standalone D3D12-on-Vulkan translation
layer) null-derefs.

## What did not work

- **Disabling D3D12** (`WINEDLLOVERRIDES "d3d12=d;d3d12core=d"`):
  CameraRaw still pulled `libvkd3d-1.dll` in through Wine's builtin
  `dxgi.dll`, which itself links vkd3d. Same crash.

- **Swapping in vkd3d-proton** (`d3d12core.dll` + `d3d12.dll` from the
  bundle's `lib/wine/vkd3d-proton/`, set `d3d12=n`): vkd3d-proton is
  self-contained, but Wine's builtin `dxgi.dll` *still* reaches
  `libvkd3d-1.dll` for its own D3D12 swapchain path. The crash address
  was byte-identical — `libvkd3d-1.dll+0x3c5d0`. (`libvkd3d-1.dll` in
  the prefix already matches the bundle; it is not a stale build — the
  bundled vkd3d simply faults here.)

System Vulkan is healthy: AMD Radeon 780M, RADV driver, Vulkan 1.4.
The bug is in Wine's vkd3d, not the GPU stack.

## What worked — turn off LR's GPU acceleration

`CameraRaw` only touches D3D12 because LR is configured to use the
GPU. LR stores that in:

```
~/.wine_adobe/drive_c/users/steamuser/AppData/Roaming/Adobe/
  Lightroom CC/Preferences/Lightroom CC Preferences.agprefs
```

Set, with LR not running:

```
gpu4setting        = "off"      (was "auto")
gpuSupported       = false      (was true)
useGPUforDisplayCB = false      (was true)
```

With the GPU off, CameraRaw never creates a D3D12 device, never
touches `dxgi`/`vkd3d`, and renders on the CPU instead. LR shows a
"Enabling GPU … will improve performance" banner — expected; the CPU
path is fully functional, just slower.

## Result — photo editing works

With the GPU disabled, LR:

- Opens a photo into the single-photo loupe / edit view, full-size
- Opens the Compare view (multiple photos side by side)
- Opens the Presets panel and the Edit panel (Light / Color / Effects
  / Detail develop sliders)
- **Edits photos** — dragging the Exposure slider visibly darkens the
  image in real time

All crash-free, on CPU rendering.

## Status

Lightroom CC runs on Arch Linux under Wine: it launches, signs in,
authenticates against Adobe Creative Cloud, loads its full UI,
browses the local filesystem, opens and displays photos, and edits
them with the develop controls.

Known limitation: GPU acceleration is off. Wine's D3D12→Vulkan
(`libvkd3d-1.dll`) faults inside CameraRaw's GPU pipeline. Re-enabling
the GPU would need that Wine vkd3d bug fixed; until then LR edits on
the CPU.
