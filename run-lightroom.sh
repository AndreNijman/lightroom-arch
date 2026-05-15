#!/usr/bin/env bash
# Run Adobe Lightroom under Wine on Arch Linux.
#
# Working configuration reached after attempts 1-6. See docs/.
#
# Stack:
#  - PhialsBasement patched Wine 10.0 (bundled binary at ~/opt/wine-adobe)
#  - d2d1.dll patched: D2D1ColorManagement effect registered + dwrite/
#    xmllite/ole32 changed from delay-imports to normal imports
#    (the delay-load helper crashed against the bundled Wine loader)
#  - Wine builtin dwrite (native Windows DWrite.dll infinite-recurses)
#  - WineD3D, NOT DXVK (DXVK caused a null-pointer crash at
#    lightroom.exe+0x28231C during AgKernel Lua startup)
#  - Microsoft Edge WebView2 runtime copied into the prefix; LR needs it
#    for the account / sign-in UI
#  - X11 driver: UseXVidMode=N (XVidMode assertion crash on Hyprland)

set -u

WINE=~/opt/wine-adobe/files/bin/wine
export WINEPREFIX=$HOME/.wine_adobe
export WEBVIEW2_BROWSER_EXECUTABLE_FOLDER='C:\webview2'
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d;dwrite=b;d3d11=b;dxgi=b;d3d10core=b;d3d9=b"
export WINEDEBUG=-all

LR_DIR="$WINEPREFIX/drive_c/Program Files/Adobe/Adobe Lightroom CC"

# Kill any stale Wine processes from a previous run.
"$(dirname "$WINE")/wineserver" -k9 2>/dev/null || true
sleep 1

cd "$LR_DIR" || exit 1
exec "$WINE" lightroom.exe
