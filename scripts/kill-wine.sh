#!/usr/bin/env bash
# Kill every process belonging to the bundled wine-adobe Wine.
#
# `wineserver -k9` is not reliable here: it only reaches processes that
# are still attached to the wineserver it can find, and Lightroom leaves
# orphaned explorer.exe / helper processes that survive it. Those stale
# processes accumulate across launches -- each one owns a virtual-desktop
# window, so the screen fills with zombie "Adobe - Wine Desktop" windows
# and a new Lightroom hands off to a stale instance instead of starting
# clean.
#
# A wine'd process has its /proc/PID/exe pointing at the Wine loader
# inside the install directory, regardless of the Windows-style command
# line it reports. Matching on that reaches every one of them.

WINE_ROOT="${WINE_ROOT:-$HOME/opt/wine-adobe}"

# Ask wineserver to shut the prefix down gracefully first.
WINEPREFIX="${WINEPREFIX:-$HOME/.wine_adobe}" \
    "$WINE_ROOT/files/bin/wineserver" -k 2>/dev/null || true
sleep 1

# Then SIGKILL anything still running out of the install directory.
for _ in 1 2 3; do
    left=0
    for p in $(pgrep -u "$USER" 2>/dev/null); do
        exe=$(readlink "/proc/$p/exe" 2>/dev/null) || continue
        case "$exe" in
            "$WINE_ROOT"/*) kill -9 "$p" 2>/dev/null; left=$((left + 1)) ;;
        esac
    done
    [ "$left" -eq 0 ] && break
    sleep 1
done
