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
#    builtin (d3d12=b;d3d12core=b).
#  - lightroom.exe binary-patched: COM null-deref at +0x28231C guarded
#    (scripts/patches/patch-lightroom-com-nullcheck.py)
#  - AdobeGrowthSDK.dll binary-patched: SetThreadpoolTimerEx import
#  - rebuilt mf/mfplat/mfreadwrite in the prefix (Media Foundation)
#  - Microsoft Edge WebView2 runtime copied into the prefix (sign-in UI)
#  - X11 driver: UseXVidMode=N (XVidMode assertion crash on Hyprland)
#  - GPU acceleration is OFF in LR's preferences. Wine's D3D12 preview
#    present path flashes between the image and an empty canvas while
#    editing; CameraRaw renders on the CPU instead (see attempt 11).
#  - The Wine virtual desktop is sized to the monitor and fullscreened
#    so its framebuffer maps 1:1 to physical pixels (crisp UI).

set -u

WINE=~/opt/wine-adobe/files/bin/wine
export WINEPREFIX=$HOME/.wine_adobe
export WEBVIEW2_BROWSER_EXECUTABLE_FOLDER='C:\webview2'
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d;dwrite=b;d3d11=b;dxgi=b;d3d10core=b;d3d9=b;d3d12=b;d3d12core=b"
export WINEDEBUG=-all

LR_DIR="$WINEPREFIX/drive_c/Program Files/Adobe/Adobe Lightroom CC"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Kill stale Wine processes left by previous runs. `wineserver -k9` is
# not enough on its own -- Lightroom leaks orphaned explorer.exe helpers
# that survive it and accumulate across launches. See scripts/kill-wine.sh.
WINE_ROOT=~/opt/wine-adobe bash "$SCRIPT_DIR/scripts/kill-wine.sh"

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
        WINE_ROOT=~/opt/wine-adobe bash "$SCRIPT_DIR/scripts/kill-wine.sh"
    fi
fi

cd "$LR_DIR" || exit 1
"$WINE" lightroom.exe &
LR_PID=$!

# Once the Wine desktop window maps, fullscreen it so the tiler never
# resizes the host window -- a resized window re-triggers Wine's
# framebuffer scaling. This is done as a dispatch on the live window
# (not a windowrule): the window title is empty at map time, and a
# static `fullscreen` windowrule is not supported by current Hyprland.
if command -v hyprctl >/dev/null 2>&1; then
    (
        for _ in $(seq 1 60); do
            addr=$(hyprctl clients -j 2>/dev/null | python3 -c '
import json, sys
wins = [c for c in json.load(sys.stdin)
        if c.get("class") == "steam_proton"
        and c.get("size", [0, 0])[0] > 200]
if wins:
    print(max(wins, key=lambda c: c["size"][0] * c["size"][1])["address"])
' 2>/dev/null)
            if [ -n "$addr" ]; then
                hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1
                hyprctl dispatch fullscreen 0 >/dev/null 2>&1
                break
            fi
            sleep 1
        done
    ) &
fi

wait "$LR_PID"
