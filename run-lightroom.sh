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
#  - GPU acceleration is ON. Wine's winex11 is patched (wine-patches/) so
#    the parent window-surface flush no longer overpaints CameraRaw's
#    offscreen D3D child swapchain -- that race was the develop-edit
#    flicker. The same patched winex11.so also fixes window-manager close:
#    a WM close request on the virtual desktop is now routed to the focused
#    application window (so the Hyprland close shortcut quits Lightroom)
#    instead of triggering a vetoable session logoff Lightroom stalls. This
#    script installs the patched winex11.so (see attempts 12-15). If you
#    ever need to revert, restore winex11.so.orig.
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

# Clean up every bundled-Wine process when this script exits -- including
# the explorer.exe desktop host and the service helpers that linger after
# lightroom.exe itself quits. Lightroom can be closed three ways (its
# titlebar close button, the Hyprland close shortcut, or this script being
# interrupted); in each case `wait` below returns once lightroom.exe is
# gone, and this trap then tears down the leftovers so no zombie
# virtual-desktop window or stale wineserver survives into the next run.
trap 'WINE_ROOT=~/opt/wine-adobe bash "$SCRIPT_DIR/scripts/kill-wine.sh" >/dev/null 2>&1' EXIT INT TERM HUP

# Kill stale Wine processes left by previous runs. `wineserver -k9` is
# not enough on its own -- Lightroom leaks orphaned explorer.exe helpers
# that survive it and accumulate across launches. See scripts/kill-wine.sh.
WINE_ROOT=~/opt/wine-adobe bash "$SCRIPT_DIR/scripts/kill-wine.sh"

# Install the patched winex11.so. It carries two fixes (see wine-patches/
# and docs/attempt-14 / attempt-15): the D3D child-swapchain flicker fix
# (the stock driver overpaints CameraRaw's offscreen preview during a
# parent UI repaint) and the window-manager close fix (a close request on
# the virtual desktop is routed to the focused app window). Idempotent:
# only acts when the installed driver differs, keeps the stock one as
# winex11.so.orig.
PATCHED_WINEX11="$SCRIPT_DIR/wine-patches/winex11.so"
TARGET_WINEX11=~/opt/wine-adobe/files/lib/wine/x86_64-unix/winex11.so
if [ -f "$PATCHED_WINEX11" ] && [ -f "$TARGET_WINEX11" ] \
   && ! cmp -s "$PATCHED_WINEX11" "$TARGET_WINEX11"; then
    [ -f "$TARGET_WINEX11.orig" ] || cp "$TARGET_WINEX11" "$TARGET_WINEX11.orig"
    chmod u+w "$TARGET_WINEX11" 2>/dev/null || true
    cp "$PATCHED_WINEX11" "$TARGET_WINEX11"
    echo "run-lightroom: installed patched winex11.so (flicker + close fix)"
fi

# Install the patched uiautomationcore.dll. Lightroom calls
# UiaDisconnectAllProviders() during shutdown; stock Wine never exported
# it, so the call hit an unimplemented-stub abort and Lightroom failed to
# terminate -- the close button and close shortcut would stall. The patched
# DLL exports it as a no-op returning S_OK. See docs/attempt-15. Idempotent;
# keeps the stock DLL as uiautomationcore.dll.orig at each target.
PATCHED_UIA="$SCRIPT_DIR/wine-patches/uiautomationcore.dll"
for TARGET_UIA in ~/opt/wine-adobe/files/lib/wine/x86_64-windows/uiautomationcore.dll \
                  "$WINEPREFIX/drive_c/windows/system32/uiautomationcore.dll"; do
    if [ -f "$PATCHED_UIA" ] && [ -f "$TARGET_UIA" ] \
       && ! cmp -s "$PATCHED_UIA" "$TARGET_UIA"; then
        [ -f "$TARGET_UIA.orig" ] || cp "$TARGET_UIA" "$TARGET_UIA.orig"
        chmod u+w "$TARGET_UIA" 2>/dev/null || true
        cp "$PATCHED_UIA" "$TARGET_UIA"
        echo "run-lightroom: installed patched uiautomationcore.dll (close fix)"
    fi
done

# Match Wine's virtual desktop to the active monitor's pixel resolution.
# If the desktop is smaller than the host window, Wine bitmap-upscales
# its framebuffer to fill the window -- the UI looks blurry and aliased.
# Sizing the desktop to the monitor and fullscreening the host window
# maps the framebuffer 1:1 to physical pixels, so the UI stays crisp.
# Note: this reads the monitor once, at launch. If you later move
# Lightroom to a different-resolution display, rerun this script.
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
