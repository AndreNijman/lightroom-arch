# Attempt 12: GPU-On Develop-Edit Flicker — Real Root Cause

Attempt 11 made the develop-edit flicker go away by turning Lightroom's
GPU acceleration **off** (CameraRaw renders the preview on the CPU). That
worked but was a workaround — it disabled the feature instead of fixing
the bug. This attempt diagnoses *why* the GPU path flickers, at the Wine
source level, and is honest about what fixing it actually requires.

## The symptom

GPU acceleration on. Open a photo in the Develop module, drag a slider.
The preview flashes rapidly between the photo and Lightroom's empty grey
loupe canvas while the slider moves, settling once the drag stops.

## Experiment matrix

LR launched four ways, each dragged with an automated `xdotool` sweep of
the Exposure slider while the screen was captured at 60 fps. Each frame
classified image-vs-blank by the luminance p97-p3 spread of the preview
region (a flat canvas has spread ~6; a rendered photo keeps a wide
spread regardless of how the edit changes its brightness).

| D3D stack            | Wine virtual desktop | Rootless (no desktop) |
|----------------------|----------------------|-----------------------|
| Wine builtin D3D12   | flickers 65/293      | flickers 59/294       |
| vkd3d-proton + DXVK  | preview never renders (black) | preview never renders (black) |

Findings:

1. **The virtual desktop is not the cause.** Builtin-D3D12 flickers the
   same with the desktop on or off — attempt 11 had implied the desktop
   blit was involved; it is not.
2. **The matched Proton stack is worse, not better.** With vkd3d-proton's
   `d3d12`/`d3d12core` and DXVK's `dxgi` (the combo every Proton game
   uses), Lightroom launches and creates a swapchain but the preview is
   never composited onto the window at all — permanently black.
3. The "blank" frames are not pure black. They are a uniform grey of
   luminance ~40 — Lightroom's empty loupe canvas, i.e. the **parent
   window showing through**. The D3D12-rendered preview is *absent* in
   those frames, not corrupted.

## Trace: the D3D12 layer is innocent

Launched with `WINEDEBUG=+dxgi,+vulkan,fixme+d3d12`, one ~3 s slider drag
(34,730 trace lines):

- `d3d12_swapchain_Present`: 81 calls
- `vkQueuePresentKHR`: 79, `vkAcquireNextImageKHR`: 79 — clean 1:1
- `vkCreateSwapchainKHR` / `vkDestroySwapchainKHR`: **0**
- `ResizeBuffers`: **0**

The D3D12 swapchain is created once (`d3d12_swapchain_create`, Vulkan
swapchain extent 1328x908, 3 user buffers, swap effect FLIP_DISCARD) and
**never recreated or resized during the drag**. The dxgi/d3d12 present
path does clean, correct work — 79 presents, 79 Vulkan presents.

This rules out the swapchain-recreation theories: there is no
`VK_ERROR_OUT_OF_DATE_KHR` recreate loop, no stale-image retry. The bug
is downstream of D3D12, in how Wine gets the rendered surface onto the
screen.

## Root cause: Wine composites D3D child windows offscreen, racing the parent

CameraRaw renders the Develop preview into a D3D12 swapchain bound to a
**child HWND** inside Lightroom's window (the loupe area is a child
window, the surrounding UI is its parent).

Wine's X11 driver decides how to put a child window's GPU output on
screen in `dlls/winex11.drv/init.c`, `needs_offscreen_rendering()`:

```c
/* ... */
if (NtUserGetAncestor( hwnd, GA_PARENT ) != NtUserGetDesktopWindow())
    return TRUE; /* child window, needs compositing */
```

For **any** child window this returns TRUE unconditionally. That forces
the "offscreen" path in `client_surface_update_offscreen()`: the child's
Vulkan output goes to an XComposite-redirected offscreen window, and on
every present Wine copies it onto the parent's X drawable with a GDI
`NtGdiStretchBlt` (`X11DRV_client_surface_present()` →
`set_dc_drawable()` + `StretchBlt`).

During a slider drag two things write to the *same* parent X drawable:

- Lightroom's own UI repaints — the grey loupe-canvas background, the
  slider, the changing value text — continuously, on the GUI thread.
- Wine's per-present `StretchBlt` of the D3D12 preview, ~26 times/sec.

These race. When Lightroom repaints the grey canvas and the next
preview `StretchBlt` has not landed yet, the grey shows. The preview
reappears on the next present. Continuous repaint + continuous present =
the flashing. When CameraRaw stops presenting (the drag settles), the
last `StretchBlt` stays put and the preview is stable.

This single mechanism explains every observation:

- flicker only while editing — needs *both* continuous re-render and
  continuous UI repaint;
- blank = grey loupe canvas — it is literally the parent drawable's own
  GDI content;
- rootless and virtual-desktop flicker identically — the offscreen
  child compositing is the same in both;
- GPU-off never flickers — with no D3D12 child swapchain, CameraRaw's
  CPU output is drawn straight into Lightroom's normal window surface;
  there is no offscreen child window and no `StretchBlt` race.

The vkd3d-proton + DXVK stack being **permanently black** is a separate,
unexplained observation. `win32u_vkQueuePresentKHR` calls
`client_surface_present()` unconditionally for every swapchain, so the
offscreen `StretchBlt` composite should run for the Proton stack too —
the "black" is therefore *not* simply "the composite never runs". It may
be a different child-window/DXVK interaction; it was not traced to a
cause here and is noted only to record that the matched Proton stack is
not a usable alternative.

Confirmed against an `WINEDEBUG=+x11drv` trace of a drag: the
`SET_DRAWABLE` escape (`set_dc_drawable`, the first step of the
offscreen `StretchBlt` present) fires ~68 times during a one-second
drag, and `needs_offscreen_rendering` is exercised — the offscreen
client-surface present path is active throughout editing.

(Source line numbers above are from a Valve-Wine checkout near the
bundled build; the bundled Proton build is a slightly different commit,
so exact lines may shift, but the `needs_offscreen_rendering` /
`client_surface` offscreen-compositing structure is the same.)

## What a real fix requires

The bug is **not** in `dxgi`/`d3d12`/`d3d12core` (the PE DLLs that can be
swapped per-prefix). It is in `winex11.drv` — a Unix-side Wine component.
Two fix directions:

1. **Narrow `needs_offscreen_rendering()`** so a child window only goes
   offscreen when it is actually overlapped by siblings — return
   `needs_client_window_clipping(hwnd)` instead of an unconditional
   `TRUE` for child windows. A non-overlapped preview then becomes a
   real attached X subwindow, composited by the X server / Hyprland, no
   `StretchBlt`, no race.
2. **Re-composite client surfaces after a parent paint** — when the
   parent window surface is flushed, re-blit overlapping client surfaces
   on top, so a parent repaint cannot leave the child region stale.

Both require patching and rebuilding `winex11.drv`, which means building
Wine from source to match the bundled Proton build's ABI. Attempt 5
found a full WoW64-style rebuild produced a broken Wine; a targeted
single-component rebuild against the matching commit is the open
question this diagnosis hands to the next attempt.

## Status

Root cause **identified precisely** and backed by traces — a real
advance over attempt 11's admitted "observation, not a confirmed
diagnosis." The fix is a `winex11.drv` source change; whether it can be
built and dropped into the bundled Proton Wine without the attempt-5
breakage is the remaining work. Until that lands, GPU-off (attempt 11)
remains the shipping configuration — now understood as a workaround for
a specific, located Wine bug rather than a mystery.
