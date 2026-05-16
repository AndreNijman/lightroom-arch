#!/usr/bin/env bash
# install-cc-desktop.sh — install Adobe Creative Cloud Desktop under Wine
# from the bundled installer, with NO rsync from a Windows partition.
#
# Status: WORK IN PROGRESS (attempt 17 — see docs/attempt-17-cc-desktop.md).
# This script automates every step that is known to work:
#   * builds a clean Wine prefix on the bundled patched Wine
#   * applies the XVidMode / vkd3d / patched-DLL fixes
#   * sets the registry tweaks the Adobe installer needs
#   * launches the Creative Cloud Desktop installer (Set-up.exe) and, the
#     instant the installer extracts its UI, rewrites index.html's
#     X-UA-Compatible meta from `chrome=1` to `IE=11` — this is the fix
#     that gets Wine's mshtml into IE11 compat mode so the installer's
#     ES6 React bundle parses and runs (was a hard SyntaxError before).
#
# Known remaining wall: the installer's React UI runs but the embedded
# WebBrowser stays hidden behind the native teal splash because the app
# does not reach its "ready" state (platform mis-detection / catalog).
# See docs/attempt-17-cc-desktop.md. Until that is solved this script
# gets you a running-but-not-interactive installer.

set -u

WINE=~/opt/wine-adobe/files/bin/wine
WINESERVER=~/opt/wine-adobe/files/bin/wineserver
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine_cc}"
export WINEARCH=win64
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER_DIR="$PROJECT_ROOT/installers/ACCCx_extracted"
SETUP_EXE="$INSTALLER_DIR/Set-up.exe"

log() { printf 'install-cc-desktop: %s\n' "$*"; }

[ -x "$WINE" ]        || { log "bundled Wine missing: $WINE"; exit 1; }
[ -f "$SETUP_EXE" ]   || { log "CC installer missing: $SETUP_EXE
  extract installers/ACCCx5_10_0_573.zip into installers/ACCCx_extracted/"; exit 1; }

# --- always start from a clean slate -------------------------------------
WINE_ROOT=~/opt/wine-adobe bash "$SCRIPT_DIR/kill-wine.sh" >/dev/null 2>&1
sleep 1

# --- 1. create the prefix ------------------------------------------------
if [ ! -d "$WINEPREFIX/drive_c" ]; then
    log "creating Wine prefix $WINEPREFIX"
    WINEDEBUG=-all "$WINE" wineboot --init >/dev/null 2>&1
    "$WINESERVER" -w
fi

# --- 2. XVidMode off (assertion crash on Hyprland/XWayland) --------------
# wine reg itself crashes with the XVidMode bug, so patch user.reg directly
# while the wineserver is down.
if ! grep -q 'X11 Driver' "$WINEPREFIX/user.reg" 2>/dev/null; then
    log "disabling XVidMode in user.reg"
    "$WINESERVER" -k >/dev/null 2>&1; sleep 1
    printf '\n[Software\\\\Wine\\\\X11 Driver]\n"UseXVidMode"="N"\n"UseXRandR"="Y"\n' \
        >> "$WINEPREFIX/user.reg"
fi

# --- 3. Wine internal vkd3d bridge DLLs ----------------------------------
# winetricks vkd3d ships only d3d12/d3d12core; Wine's wined3d also needs
# the internal libvkd3d bridge DLLs. Copy them from the bundle default_pfx.
DEF=~/opt/wine-adobe/files/share/default_pfx/drive_c/windows
for sub in system32 syswow64; do
    [ -d "$WINEPREFIX/drive_c/windows/$sub" ] || continue
    for f in libvkd3d-1.dll libvkd3d-shader-1.dll; do
        [ -f "$WINEPREFIX/drive_c/windows/$sub/$f" ] && continue
        [ -f "$DEF/$sub/$f" ] && cp "$DEF/$sub/$f" "$WINEPREFIX/drive_c/windows/$sub/"
    done
done

# --- 4. patched Wine DLLs (shared with the Lightroom config) -------------
# winex11.so is a bundle-wide Unix driver; d2d1 / uiautomationcore are PE
# builtins. run-lightroom.sh installs the same set; do it here too so the
# CC prefix gets the window-close and UI-curve fixes.
PWX="$PROJECT_ROOT/wine-patches/winex11.so"
TWX=~/opt/wine-adobe/files/lib/wine/x86_64-unix/winex11.so
if [ -f "$PWX" ] && [ -f "$TWX" ] && ! cmp -s "$PWX" "$TWX"; then
    [ -f "$TWX.orig" ] || cp "$TWX" "$TWX.orig"
    chmod u+w "$TWX" 2>/dev/null || true; cp "$PWX" "$TWX"
    log "installed patched winex11.so"
fi
for dll in d2d1 uiautomationcore; do
    P="$PROJECT_ROOT/wine-patches/$dll.dll"
    for T in ~/opt/wine-adobe/files/lib/wine/x86_64-windows/$dll.dll \
             "$WINEPREFIX/drive_c/windows/system32/$dll.dll"; do
        [ -f "$P" ] && [ -f "$T" ] && ! cmp -s "$P" "$T" || continue
        [ -f "$T.orig" ] || cp "$T" "$T.orig"
        chmod u+w "$T" 2>/dev/null || true; cp "$P" "$T"
        log "installed patched $dll.dll"
    done
done

# --- 5. registry tweaks the Adobe installer needs ------------------------
reg() { WINEDEBUG=-all "$WINE" reg add "$@" /f >/dev/null 2>&1; }
# Run the installer inside a Wine virtual desktop so it is a single,
# screenshot-able, well-behaved top-level window.
reg 'HKCU\Software\Wine\Explorer\Desktops' /v CCInstall /t REG_SZ /d 1600x1000
reg 'HKCU\Software\Wine\Explorer'          /v Desktop   /t REG_SZ /d CCInstall
# Force the embedded WebBrowser controls into IE11 mode.
for exe in "Set-up.exe" "Creative Cloud.exe" "Creative Cloud Helper.exe"; do
    reg 'HKCU\Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION' \
        /v "$exe" /t REG_DWORD /d 0x2af9
done
# Report an IE11 Windows user agent (the React installer sniffs the UA
# for \bTrident\b / isWinPlatform to decide it is not on macOS).
reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\User Agent' \
    /ve /t REG_SZ /d 'Mozilla/5.0 (Windows NT 10.0; WOW64; Trident/7.0; rv:11.0) like Gecko'
"$WINESERVER" -w

# --- 6. launch the installer with the index.html meta fix ----------------
# Set-up.exe extracts its React UI to %TEMP%\{GUID}\ then navigates the
# embedded WebBrowser to index.html. Between those two steps we rewrite
# the X-UA-Compatible meta from chrome=1 (Wine -> IE7 compat mode, ES6
# SyntaxError) to IE=11 (Wine -> IE11 compat mode, ES6 parses). We watch
# the temp tree with inotifywait so there is no polling race.
TMP="$WINEPREFIX/drive_c/users/$(id -un)/AppData/Local/Temp"
[ -d "$TMP" ] || TMP="$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Temp"
mkdir -p "$TMP"; rm -rf "${TMP:?}/"* 2>/dev/null

(
    # wait for any index.html to be created under the temp tree, patch it
    while read -r dir _ file; do
        [ "$file" = index.html ] || continue
        idx="$dir$file"
        sleep 0.1   # let Set-up.exe finish writing the file
        python3 - "$idx" <<'PY'
import sys
p = sys.argv[1]
try:
    s = open(p, encoding="utf-8", errors="replace").read()
except OSError:
    sys.exit(0)
if "content='chrome=1'" in s:
    open(p, "w", encoding="utf-8").write(s.replace("content='chrome=1'",
                                                   "content='IE=11'"))
    print("install-cc-desktop: patched index.html meta -> IE=11")
PY
        break
    done < <(inotifywait -m -r -e create -e moved_to --format '%w %e %f' "$TMP" 2>/dev/null)
) &
WATCH_PID=$!

log "launching the Creative Cloud Desktop installer"
cd "$INSTALLER_DIR" || exit 1
WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d" WINEDEBUG=-all \
    "$WINE" Set-up.exe
RC=$?

kill "$WATCH_PID" 2>/dev/null
WINE_ROOT=~/opt/wine-adobe bash "$SCRIPT_DIR/kill-wine.sh" >/dev/null 2>&1
log "installer exited (rc=$RC)"
exit "$RC"
