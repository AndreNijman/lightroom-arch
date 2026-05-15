#!/usr/bin/env bash
# Run Adobe Lightroom (Creative Cloud desktop app) under Wine on Arch Linux.
#
# Working configuration reached after attempts 1-10. See docs/.
#
# Stack:
#  - PhialsBasement patched Wine 10.0 (bundled binary at ~/opt/wine-adobe)
#  - d2d1.dll patched: D2D1ColorManagement effect registered + dwrite/
#    xmllite/ole32 changed from delay-imports to normal imports
#  - Wine builtin dwrite (native Windows DWrite.dll infinite-recurses)
#  - WineD3D for d3d9/10/11, Wine builtin D3D12 (libvkd3d). Do NOT mix
#    vkd3d-proton's d3d12core with Wine's builtin dxgi -- Wine's dxgi
#    D3D12-swapchain code only understands Wine-libvkd3d device objects
#    and crashes on a vkd3d-proton device. Keep the whole D3D12 stack
#    builtin (d3d12=b;d3d12core=b) and GPU acceleration works.
#  - lightroom.exe binary-patched: COM null-deref at +0x28231C guarded
#    (scripts/patches/patch-lightroom-com-nullcheck.py)
#  - AdobeGrowthSDK.dll binary-patched: SetThreadpoolTimerEx import
#  - rebuilt mf/mfplat/mfreadwrite in the prefix (Media Foundation)
#  - Microsoft Edge WebView2 runtime copied into the prefix (sign-in UI)
#  - X11 driver: UseXVidMode=N (XVidMode assertion crash on Hyprland)
#  - GPU acceleration is ON in LR's preferences. Photos render and edit
#    GPU-accelerated through Wine's builtin D3D12 -> Vulkan (RADV).

set -u

WINE=~/opt/wine-adobe/files/bin/wine
export WINEPREFIX=$HOME/.wine_adobe
export WEBVIEW2_BROWSER_EXECUTABLE_FOLDER='C:\webview2'
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d;dwrite=b;d3d11=b;dxgi=b;d3d10core=b;d3d9=b;d3d12=b;d3d12core=b"
export WINEDEBUG=-all

LR_DIR="$WINEPREFIX/drive_c/Program Files/Adobe/Adobe Lightroom CC"

# Kill any stale Wine processes from a previous run. WINEPREFIX is
# exported above, so wineserver targets the right prefix.
"$(dirname "$WINE")/wineserver" -k9 2>/dev/null || true
sleep 2

# Match Wine's virtual desktop to the active monitor's pixel resolution.
# If the desktop is smaller than the host window, Wine bitmap-upscales
# its framebuffer to fill the window -- the UI looks blurry and aliased.
# Sizing the desktop to the monitor and fullscreening the host window
# maps the framebuffer 1:1 to physical pixels, so the UI stays crisp.
if command -v hyprctl >/dev/null 2>&1; then
    RES=$(hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys
mons = json.load(sys.stdin)
mon = next((m for m in mons if m.get("focused")), mons[0] if mons else None)
if mon:
    print("%dx%d" % (mon["width"], mon["height"]))
' 2>/dev/null)
    if [ -n "$RES" ]; then
        "$WINE" reg add 'HKCU\Software\Wine\Explorer\Desktops' \
            /v Adobe /t REG_SZ /d "$RES" /f >/dev/null 2>&1 || true
        "$(dirname "$WINE")/wineserver" -k9 2>/dev/null || true
        sleep 1
    fi
    # Fullscreen the Wine desktop window so the tiler never resizes it
    # (a resized host window makes Wine scale its framebuffer again).
    # Match on the window class -- it is set when the window is created,
    # whereas the title is still empty at map time so a title rule misses.
    hyprctl keyword windowrulev2 \
        'fullscreen, class:^(steam_proton)$' >/dev/null 2>&1 || true
fi

cd "$LR_DIR" || exit 1
exec "$WINE" lightroom.exe
