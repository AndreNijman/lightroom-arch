# Attempt 14: Fix the GPU-On Flicker — winex11 Flush Exclusion

Attempt 12 located the GPU-on develop-edit flicker; attempt 13's first
patch (`needs_offscreen_rendering`) was a no-op because Lightroom's
preview window is genuinely sibling-clipped, so Wine correctly keeps it
on the offscreen path. This attempt fixes it on the offscreen path
itself — and it works.

## The race, restated

CameraRaw renders the Develop preview into a D3D12 swapchain on a child
window. Wine's `winex11` composites that child "offscreen": the rendered
frame lives in an XComposite-redirected X window, and on every present
`X11DRV_vulkan_surface_presented()` (`dlls/winex11.drv/vulkan.c`)
`StretchBlt`s it onto the parent toplevel's X drawable.

The parent's own window-surface flush — `x11drv_surface_flush()` in
`dlls/winex11.drv/bitblt.c` — `XPutImage`s Lightroom's UI bitmap onto the
*same* drawable. During a slider drag Lightroom repaints its UI
continuously, so the parent flush keeps overpainting the preview region
with the grey loupe-canvas background. Between the overpaint and the next
present's `StretchBlt`, the grey shows. Continuous overpaint + ~26 fps
presents = the flashing.

The two writers race over one X drawable and nothing makes the parent
flush leave the child's pixels alone.

## The fix

Make the parent flush **not write the offscreen child's rectangle**.

`winex11` now keeps a small process-global list of offscreen Vulkan
child surfaces and the rect each one composites to (`offscreen_vk_set` /
`offscreen_vk_clear` / `x11drv_get_offscreen_vk_rects` in `vulkan.c`,
mutex-protected). `X11DRV_vulkan_surface_presented()` registers its rect
after each `StretchBlt`; detach/destroy and the non-offscreen path clear
it.

`x11drv_surface_flush()` queries that list for its toplevel X window and,
when an offscreen child overlaps, builds an X `Region` of the area it was
about to put **minus** the child rects, sets it as the GC clip for the
`XPutImage`/`XShmPutImage`, then restores the prior clip. The parent UI
still paints everywhere except the live preview rectangle; the
per-present `StretchBlt` is left as the sole writer of that rectangle.

No race, no flicker. The change is confined to `dlls/winex11.drv/`
(`vulkan.c`, `bitblt.c`, `x11drv.h`) — no ABI change, and no behaviour
change for any window that is not an offscreen Vulkan child, so the
rebuilt `winex11.so` is a safe drop-in.

## Result

Built from the bundled build's exact commit (Proton Wine `dbb32ff8`),
installed, GPU acceleration **on**. Automated Exposure-slider drags
captured at 60 fps and classified by luminance spread:

| Build                | GPU | Blank frames |
|----------------------|-----|--------------|
| stock winex11        | on  | ~65 / 293 — constant flashing |
| **patched winex11**  | on  | **0 / 293, 0 / 114, 0 / 294** |

Three runs, 700+ frames of aggressive GPU-on editing, **zero** blank
frames — every frame shows the image. The UI is intact (panels, slider,
filmstrip all render normally); the preview tracks the edit live.

## Shipping

- `wine-patches/winex11-vulkan-child-flush-fix.patch` — the source patch.
- `wine-patches/winex11.so` — the prebuilt 64-bit driver (from
  `dbb32ff8` + patch).
- `run-lightroom.sh` installs the patched driver on launch (idempotent;
  keeps the stock one as `winex11.so.orig`).
- Lightroom's GPU acceleration is re-enabled in `Lightroom CC
  Preferences.agprefs` (`gpu4setting = "auto"`, `useGPUforDisplayCB =
  true`) — the attempt-11 GPU-off workaround is withdrawn.

## Status

**Fixed.** Lightroom runs GPU-accelerated on Wine with no develop-edit
flicker. The fix is a real Wine bug fix (offscreen D3D child swapchains
racing the parent window-surface flush) — narrow, ABI-safe, and
upstreamable in principle. GPU-off is no longer needed.
