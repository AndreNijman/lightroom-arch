# Wine patches

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
