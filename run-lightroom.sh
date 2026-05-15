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

cd "$LR_DIR" || exit 1
exec "$WINE" lightroom.exe
