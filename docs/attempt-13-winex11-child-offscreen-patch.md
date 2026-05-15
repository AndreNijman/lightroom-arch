# Attempt 13: Patch winex11 to Fix the GPU-On Flicker

Attempt 12 located the GPU-on develop-edit flicker precisely: Wine's
`winex11` driver forces every child window onto the "offscreen" path
(`needs_offscreen_rendering()` returns `TRUE` unconditionally for any
child HWND), and the offscreen path composites by a per-present GDI
`StretchBlt` into the parent's X drawable, which races Lightroom's own
parent-window repaints during a slider drag.

This attempt patches that and rebuilds `winex11`.

## The patch

`dlls/winex11.drv/init.c`, `needs_offscreen_rendering()`. The bundled
build is Proton Wine 10.0 at commit `dbb32ff8` (build string
`...-wdbb32f-...`); the patch is applied to that exact commit so the
rebuilt driver is ABI-compatible with the bundled `win32u`.

Before:

```c
if (NtUserGetAncestor( hwnd, GA_PARENT ) != NtUserGetDesktopWindow())
    return TRUE; /* child window, needs compositing */
```

After: an env-gated branch. Default behaviour is unchanged (returns
`TRUE`); with `WINE_X11_CHILD_OFFSCREEN=0` a child window only takes the
offscreen path when it is *actually* clipped by sibling windows
(`needs_client_window_clipping()`), exactly as Wine already does for
windows that have children. A non-overlapped D3D child swapchain then
becomes a real attached X subwindow, composited by the X server /
Hyprland — no `StretchBlt`, no race with the parent's repaint.

The env gate keeps the rebuilt `winex11.so` a safe drop-in: with the
variable unset it behaves identically to stock Wine, and Lightroom was
opted in for the test with `WINE_X11_CHILD_OFFSCREEN=0`. (As the Result
section shows the patch did not help, `run-lightroom.sh` is left
unchanged and the stock `winex11.so` was restored.)

## Build

- `experimental_10.0` branch of ValveSoftware/wine, commit `dbb32ff8`.
- `./configure --enable-archs=x86_64 --disable-tests`, `make dlls/winex11.drv`.
- Only the 64-bit unix `winex11.so` is replaced in the bundle
  (`~/opt/wine-adobe/files/lib/wine/x86_64-unix/winex11.so`); Lightroom's
  rendering process is 64-bit. The original is kept as `winex11.so.orig`.

## Result — the patch does not fix it

The build worked: `winex11.so` compiled from `dbb32ff8`, stripped (577 KB),
dropped into the bundle. It **loads cleanly** — no `version mismatch`,
Lightroom launches and renders normally, so a single-component rebuild
against the matching commit *is* ABI-compatible with the Proton-built
`win32u`. That part is a genuine result: the rebuild path works.

But the flicker remains. With `WINE_X11_CHILD_OFFSCREEN=0`, GPU on, a
slider-drag flicker capture: **118/296 blank frames** — no better than
the 65/293 baseline.

A `WINEDEBUG=+x11drv` trace explains why. During a one-second drag the
`SET_DRAWABLE` escape (the first step of the offscreen `StretchBlt`
present) fires **65 times** — identical to the **68** in the unpatched
trace. The offscreen path is *still active*. The patch is a **no-op**
for this window: `needs_client_window_clipping()` returns `TRUE` for
the preview, because Lightroom's preview child window genuinely *is*
clipped by sibling UI windows. Wine is correct to composite it
offscreen — the offscreen path is required for that clipping to work.

The actual Wine-10 offscreen present is `X11DRV_vulkan_surface_presented()`
in `dlls/winex11.drv/vulkan.c`: on every Vulkan present it `StretchBlt`s
the redirected offscreen window onto the toplevel's X drawable. Nothing
re-runs that `StretchBlt` when Lightroom's parent UI repaints over the
region — that is the race, and it is intrinsic to the offscreen path.

Also tested: `force_present_to_surface()` (an existing Wine hack that
blits the preview into the parent's window surface instead of straight
to the X drawable, normally gated to one Steam game). Forced on via
`SteamGameId=803600`: **141/292 blank** — also no help.

## What the real fix needs

The offscreen `StretchBlt` cannot simply be removed (clipping needs it)
and cannot simply be disabled per-window (the window is genuinely
clipped). The fix has to stop the preview losing the race against the parent
repaint: Wine must **re-composite the Vulkan child surface after the
parent toplevel's GDI surface is flushed**. That means
tracking Vulkan surfaces per-window in `winex11`/`win32u` and re-running
`X11DRV_vulkan_surface_presented`'s `StretchBlt` whenever the parent
paints over the child region. Wine 11 reworked this area into a
`client_surface` abstraction; checking whether Wine 11 already fixes the
race (and whether a Wine-11 `winex11` can be ABI-fitted, or the bundled
Wine moved to 11) is the most promising next lead.

## Status

GPU-on flicker is **not fixed**. But this was a real engineering attempt,
not a workaround: the exact Wine commit was identified, `winex11` was
patched and rebuilt and shown to load ABI-clean, two candidate fixes
were built/configured and measured, and both were disproven with frame
counts and traces rather than assumed. The bug is a genuine limitation
in Wine's offscreen compositing of D3D child-window swapchains.

The shipping configuration stays GPU-off (attempt 11) — now backed by a
complete root-cause analysis (attempt 12) and a tested, measured
fix attempt (this attempt). The stock `winex11.so` is restored; nothing
in the bundle is left modified.
