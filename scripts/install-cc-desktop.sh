#!/usr/bin/env bash
# install-cc-desktop.sh — install Adobe Creative Cloud Desktop under Wine
# from the bundled installer, with NO rsync from a Windows partition.
#
# Status: WORK IN PROGRESS (attempt 17 — see docs/attempt-17-cc-desktop.md).
# This script automates every step that is known to work:
#   * builds a clean Wine prefix on the bundled patched Wine
#   * applies the XVidMode / vkd3d / patched-DLL fixes
#   * installs the patched mshtml.dll (wine-patches/mshtml-*.dll): Wine's
#     mshtml now honours FEATURE_BROWSER_EMULATION, the registry value
#     Set-up.exe sets for itself to request IE11. Without the patch Wine
#     ignored that key and ran the installer's WebBrowser in IE7 compat
#     mode, where jscript rejects the React bundle's let/const with a
#     SyntaxError. The Adobe installer runs completely UNMODIFIED — no
#     index.html rewrite, no registry pre-seeding.
#   * launches the Creative Cloud Desktop installer (Set-up.exe)
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

# patched mshtml.dll — FEATURE_BROWSER_EMULATION fix (wine-patches/README.md).
# Set-up.exe is a 32-bit PE, so the i386 build is the one that matters; the
# x86_64 build is installed too for any 64-bit host. The builtin lives in
# lib/wine/<arch>-windows; the prefix copy is belt-and-suspenders.
install_mshtml() {  # $1 = patched source, $2 = target dll
    [ -f "$1" ] && [ -f "$2" ] && ! cmp -s "$1" "$2" || return 0
    [ -f "$2.orig" ] || cp "$2" "$2.orig"
    chmod u+w "$2" 2>/dev/null || true; cp "$1" "$2"
    log "installed patched mshtml.dll ($2)"
}
MSI="$PROJECT_ROOT/wine-patches/mshtml-i386.dll"
MSX="$PROJECT_ROOT/wine-patches/mshtml-x86_64.dll"
install_mshtml "$MSI" ~/opt/wine-adobe/files/lib/wine/i386-windows/mshtml.dll
install_mshtml "$MSI" "$WINEPREFIX/drive_c/windows/syswow64/mshtml.dll"
install_mshtml "$MSX" ~/opt/wine-adobe/files/lib/wine/x86_64-windows/mshtml.dll
install_mshtml "$MSX" "$WINEPREFIX/drive_c/windows/system32/mshtml.dll"

# --- 5. registry tweaks the Adobe installer needs ------------------------
reg() { WINEDEBUG=-all "$WINE" reg add "$@" /f >/dev/null 2>&1; }
# Run the installer inside a Wine virtual desktop so it is a single,
# screenshot-able, well-behaved top-level window.
reg 'HKCU\Software\Wine\Explorer\Desktops' /v CCInstall /t REG_SZ /d 1600x1000
reg 'HKCU\Software\Wine\Explorer'          /v Desktop   /t REG_SZ /d CCInstall
# NOTE: FEATURE_BROWSER_EMULATION is intentionally NOT pre-seeded here.
# Set-up.exe writes that key for itself ("Set-up.exe"=dword:00002af9), and
# the patched mshtml.dll installed above now honours it — so the embedded
# WebBrowser reaches IE11 compat mode with the Adobe installer unmodified.
# Report an IE11 Windows user agent (the React installer sniffs the UA
# for \bTrident\b / isWinPlatform to decide it is not on macOS).
reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\User Agent' \
    /ve /t REG_SZ /d 'Mozilla/5.0 (Windows NT 10.0; WOW64; Trident/7.0; rv:11.0) like Gecko'
"$WINESERVER" -w

# --- 6. launch the installer --------------------------------------------
# No Adobe-shipped file is touched. Set-up.exe extracts its React UI to
# %TEMP%\{GUID}\ and navigates its embedded WebBrowser to index.html; the
# patched mshtml.dll honours the FEATURE_BROWSER_EMULATION key Set-up.exe
# sets for itself, so that WebBrowser runs in IE11 and the ES6 React
# bundle parses. (Wipe stale temp extractions first, hygiene only.)
TMP="$WINEPREFIX/drive_c/users/$(id -un)/AppData/Local/Temp"
[ -d "$TMP" ] || TMP="$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Temp"
mkdir -p "$TMP"; rm -rf "${TMP:?}/"* 2>/dev/null

log "launching the Creative Cloud Desktop installer"
cd "$INSTALLER_DIR" || exit 1
WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d" WINEDEBUG=-all \
    "$WINE" Set-up.exe
RC=$?

WINE_ROOT=~/opt/wine-adobe bash "$SCRIPT_DIR/kill-wine.sh" >/dev/null 2>&1
log "installer exited (rc=$RC)"
exit "$RC"
