# Attempt 2 Progress and Blockers — 2026-05-15

Documenting the progress and remaining blockers from the PhialsBasement
patched Wine approach. This is partial progress, not success.

## What worked

1. **Patched Wine (10.0) downloaded and extracted** to `~/opt/wine-adobe/files/`.
   Pre-compiled release from <https://github.com/PhialsBasement/wine-adobe-installers/releases>
   tag `fix-dropdowns` (2026-01-26).
2. **Wine prefix created** at `~/.wine_adobe` (win64).
3. **winetricks dependencies installed**: atmlib, gdiplus, msxml3, msxml6,
   vcrun2017, corefonts, vkd3d (vkd3d-proton DLLs), wininet (native), winhttp (native).
4. **Host vkd3d installed**: `sudo pacman -S vkd3d lib32-vkd3d`.
5. **libvkd3d-1.dll and libvkd3d-shader-1.dll copied** from Wine's default_pfx
   into our prefix (winetricks vkd3d only installs d3d12 DLLs, not these).
6. **CC bootstrapper downloaded** from `https://ccmdl.adobe.com/AdobeProducts/KCCC/1/win32/CreativeCloudSet-Up.exe` (805KB stub).
7. **CC Desktop 5.10.0.573 full installer ZIP downloaded** (328MB) from
   `https://ccmdl.adobe.com/AdobeProducts/KCCC/CCD/5_10_0/win64/ACCCx5_10_0_573.zip`.
   Extracted, includes `Set-up.exe` (2.9MB, Feb 2023) and all ADC packages.
8. **CC Installer window appears** — patched Wine successfully launches the
   installer, window is created (verified via xdotool).

## What's still blocking

### Blocker 1: Adobe HTTPS/TLS in Wine wininet

The KCCC/1 stub bootstrapper failed at `wininet.dll` with errors:

- `12157` — `ERROR_INTERNET_SECURITY_CHANNEL_ERROR` (initial, with builtin wininet)
- `12030` — `ERROR_INTERNET_CONNECTION_ABORTED` (after `winetricks wininet`)
- `12175` — modern TLS failure

Root cause: native Microsoft `wininet.dll` from Win7 era doesn't speak
TLS 1.2+, which Adobe servers now require. `winetricks ie8_tls12` (the
TLS 1.2 patch for IE8/wininet) is 32-bit only — won't apply to a `win64`
prefix.

### Blocker 2: Blue/blank installer window (CC Desktop 5.10 Set-up.exe)

The Set-up.exe launches and shows a window titled "Creative Cloud
Installer" sized 1280x739. The window renders a teal/blue background
but no UI content (no buttons, no text, no login form). This is the
documented "Adobe blue/white screen" issue in the Wine community.

Logs show:

- `WAM.log` confirms `Application initialized successfully`
- WAM tries POST to `cc-api-data.adobe.io:443ingest` and gets
  `HTTP_Status:0 HttpCommunicator error:70`

The blue screen is downstream of the same network/TLS problem — the
installer can't fetch its dynamic UI assets and config from Adobe servers.

### Blocker 3: Hyprland + XWayland window management

Wine's installer windows are override-redirect XWayland subwindows. They
render via XWayland but are not mapped as Hyprland clients — invisible
in `hyprctl clients`, not on a workspace. Andre still sees them painted
on screen but they tile oddly.

Wine virtual desktop mode (`explorer /desktop=Adobe,1280x800`) crashes
with `xf86vm_free_modes` assertion in `winex11.drv` — not usable.

## What we tested but didn't help

- `winetricks wininet` (native Win7 DLL) — got past first TLS failure but ran into next layer of TLS failures.
- `winetricks winhttp` (native) — installed but Adobe uses wininet not winhttp.
- `winetricks ie8_tls12` — fails on win64 prefix.
- Wine virtual desktop mode — crashes patched Wine 10.0.

## Strategic pivot needed

The bootstrapper-and-CC-Desktop path is gated on TLS support that
native wininet from Win7 can't provide and Wine's builtin wininet
doesn't satisfy Adobe's stack.

Next candidates:

1. **Direct Lightroom Classic installer**, no CC Desktop wrapper, that
   does its own HTTPS without depending on the old wininet path.
2. **bpawnzZ bundled installer** — Lightroom CC 7.5 (2018-era) bundled
   in a community repo (copyright-grey but technically functional).
3. **Different Wine fork** with modern TLS in wininet — there's no such
   fork I'm aware of.
4. **TLS proxy** — intercept Wine's HTTPS and re-encrypt with modern TLS.
   Possible with mitmproxy but complex.
