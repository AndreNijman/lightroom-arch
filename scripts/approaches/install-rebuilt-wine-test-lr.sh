#!/usr/bin/env bash
# Install rebuilt Wine 10.0 + relaunch LR.
# Prereq: $HOME/wine-build/wine-src/build successfully built (make -j16 done).

set -euo pipefail

BUILD=$HOME/wine-build/wine-src/build
INSTALL_PREFIX=$HOME/opt/wine-adobe-built
WINEPREFIX=$HOME/.wine_adobe
LR_EXE="$WINEPREFIX/drive_c/Program Files/Adobe/Adobe Lightroom Classic/Lightroom.exe"
LOG=$HOME/Projects/lightroom-arch/logs/lr-rebuilt.log

echo "[1/5] kill stale wine"
pkill -9 -f wine 2>/dev/null || true
pkill -9 -f lightroom 2>/dev/null || true
sleep 1

echo "[2/5] close stale wine windows in hyprland"
hyprctl clients -j 2>/dev/null \
  | jq -r '.[] | select(.class | test("(?i)wine|lightroom|adobe")) | .address' \
  | while read -r a; do hyprctl dispatch closewindow "address:$a" || true; done
sleep 1

echo "[3/5] install rebuilt wine"
cd "$BUILD"
make install >> "$LOG" 2>&1

echo "[4/5] check binaries"
"$INSTALL_PREFIX/bin/wine" --version
"$INSTALL_PREFIX/bin/wine64" --version 2>/dev/null || true
ls "$INSTALL_PREFIX/lib/wine/x86_64-windows/d2d1.dll" \
   "$INSTALL_PREFIX/lib/wine/x86_64-windows/dwrite.dll" \
   "$INSTALL_PREFIX/lib/wine/x86_64-windows/ntdll.dll"

echo "[5/5] launch lightroom with rebuilt wine"
export WINEPREFIX
export WINEDEBUG=+d2d,+dwrite,+module,err+all
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d"
setsid "$INSTALL_PREFIX/bin/wine" "$LR_EXE" </dev/null > "$LOG" 2>&1 & disown
echo "PID=$!"
echo "Log: $LOG"
