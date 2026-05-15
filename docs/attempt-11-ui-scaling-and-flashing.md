# Attempt 11: Crisp UI and the Develop-Edit Flashing

Two issues reported against the working GPU-accelerated build:

1. The whole Lightroom UI looked pixelly / aliased, with no antialiasing.
2. While editing a photo (dragging Develop sliders) the preview flashed
   rapidly between the image and black, settling once the drag stopped.

## Issue 1 — pixelly UI: virtual-desktop upscaling

Lightroom runs inside a Wine virtual desktop (`explorer.exe /desktop`).
The desktop's framebuffer resolution is fixed by the registry value
`HKCU\Software\Wine\Explorer\Desktops\Adobe`. It was set to `1280x800`,
while the host window on the 1920x1200 monitor was the full monitor
size. Wine bitmap-upscaled the 1280x800 framebuffer 1.5x to fill the
window — every pixel of UI was stretched, so text and controls looked
soft and aliased.

**Fix.** `run-lightroom.sh` now queries the active monitor with
`hyprctl` and sets the desktop resolution to its exact pixel size, then
fullscreens the Wine desktop window (post-launch `hyprctl dispatch`,
because the window's title is empty at map time and current Hyprland
rejects a static `fullscreen` windowrule). The framebuffer maps 1:1 to
physical pixels — the UI is now crisp.

## Stale-process cleanup

A side problem surfaced while iterating: `wineserver -k9` does not
reliably kill Lightroom's processes. It leaves orphaned `explorer.exe`
helpers alive; 55 of them had accumulated over one working session.
Each owns a virtual-desktop window, so zombie "Adobe - Wine Desktop"
windows pile up and a freshly launched Lightroom hands off to a stale
instance instead of starting clean.

`scripts/kill-wine.sh` kills every process whose `/proc/PID/exe`
resolves into the bundled Wine install — that identifies them
regardless of the Windows-style command line they report.
`run-lightroom.sh` calls it before every launch.

## Issue 2 — Develop-edit flashing: the GPU preview path

While dragging Develop sliders the preview flashed rapidly between the
image and an empty canvas.

**Reproduction.** A photo is loaded into the loupe, then `xdotool`
drags the Exposure / Contrast / Shadows sliders fast and wide while
`wf-recorder` captures the screen at 60fps. Each frame is classified
image-vs-empty by the robust luminance spread of the preview region
(97th minus 3rd percentile) — empty canvas is flat (spread ~0), any
rendered image keeps a spread regardless of how dark the edit makes it.
Mean brightness and variance both fail here: an exposure edit changes
the image's own brightness and contrast and gets misread as a flash.

**Result.**

| Run | Flicker frames | Transitions |
|-----|----------------|-------------|
| GPU on  | 83 / 258  | 35 — constant flashing |
| GPU on  | 260 / 485 | 19 + long stuck-empty runs |
| GPU off | 0 / 435   | 0 — no flicker at all |

With the GPU on, the preview drops to the empty canvas for ~3 frames
between every ~7 rendered frames throughout the drag, and sometimes
sticks empty for a second after it. With the GPU off, every one of 435
frames of aggressive editing shows the image — zero flicker.

**Cause.** Lightroom's CameraRaw engine renders the Develop preview
with Direct3D 12. Under Wine that preview is presented through the
builtin D3D12 path (`dxgi` + `libvkd3d`), and the present blanks
between renders — the window shows Lightroom's empty loupe canvas
until the next D3D12 frame lands. No vkd3d error is logged; it is a
present/compositing timing problem, not a crash. (Observation, not a
confirmed diagnosis: the bundled vkd3d returns `E_NOINTERFACE` for
`ID3D12CommandQueueDownlevel` at startup — the interface for
presenting D3D12 to a window without a DXGI swapchain. CameraRaw then
proceeds via the swapchain path; whether that path is the one
blanking was not traced.)

**Fix.** Disable Lightroom's GPU acceleration. In
`Lightroom CC Preferences.agprefs` (with Lightroom closed):

```
gpu4setting        = "off"     (was "auto")
gpuSupported       = false     (was true)
useGPUforDisplayCB = false     (was true)
```

CameraRaw then renders the Develop preview on the CPU. Editing is
slightly slower than a working GPU path would be, but it is correct:
the preview updates in place with no flashing. This supersedes
attempt 10's "GPU on" conclusion — attempt 10 confirmed the GPU path
did not crash, but did not catch that it flickers while editing.

Re-enabling GPU acceleration cleanly would need Wine's D3D12 present
path fixed; until then Lightroom edits on the CPU.

## Status

Both reported symptoms are gone. The pixelly UI is genuinely fixed —
the framebuffer maps 1:1. The flashing is **worked around, not fixed
at the source**: GPU acceleration is disabled so CameraRaw renders the
preview on the CPU. The underlying Wine D3D12 present bug remains; if
GPU-accelerated editing is wanted back, that present path would need
to be fixed.

Verified flicker-free on both a JPEG and a real 18 MB Nikon D7000 NEF
raw: 0 blank frames across 435 (JPEG) and 233 (NEF) captured frames of
slider editing. The NEF decoded and displayed within a few seconds and
its preview visibly tracked the Exposure drag — CPU rendering is
slower than a working GPU path would be, but it keeps pace well enough
to edit.

