# Attempt 2 Technical Findings — 2026-05-15

Concrete technical contributions from this attempt, useful regardless of
whether Lightroom Classic ultimately ran.

## 1. XVidMode assertion crash on Hyprland + XWayland + patched Wine 10.0

Patched Wine 10.0 (PhialsBasement build) crashes inside `winex11.drv` when
launched under Hyprland's XWayland with this assertion:

```text
../src-wine/dlls/winex11.drv/xvidmode.c:164: xf86vm_free_modes:
  Assertion `modes[0].dmDriverExtra == sizeof(XF86VidModeModeInfo *)' failed.
```

Cause: XWayland's XFree86 VidMode extension returns mode structs whose
`dmDriverExtra` field size mismatches what Wine 10.0's xvidmode handler
expects. The assertion fails on every `wine reg add` and every installer launch.

**Fix:** Disable the XVidMode extension via `user.reg`. `wine reg` itself
crashes with this bug, so editing `user.reg` directly is required:

```text
[Software\\Wine\\X11 Driver]
"UseXVidMode"="N"
"UseXRandR"="Y"
```

After this, all Wine commands work cleanly.

## 2. libvkd3d-1.dll / libvkd3d-shader-1.dll missing from new prefix

`winetricks vkd3d` installs `d3d12.dll` and `d3d12core.dll` (vkd3d-proton
public DirectX 12 API) but does NOT install `libvkd3d-1.dll` /
`libvkd3d-shader-1.dll` (Wine's internal vkd3d bridge DLLs).

Patched Wine's `wined3d.dll` depends on these internal DLLs.
Without them, every Wine application that touches DirectX (anything
using GDI+, DirectComposition, etc.) gets cascading failures:

```text
err:module:import_dll Library libvkd3d-1.dll not found
err:module:import_dll Library wined3d.dll not found
err:module:import_dll Library dxgi.dll not found
err:ole:apartment_add_dll couldn't load wbemprox.dll
```

**Fix:** Install host `vkd3d` and `lib32-vkd3d` (`sudo pacman -S
vkd3d lib32-vkd3d`), AND copy Wine's bundled internal DLLs from the
default prefix:

```sh
cp ~/opt/wine-adobe/files/share/default_pfx/drive_c/windows/system32/libvkd3d-1.dll \
   ~/.wine_adobe/drive_c/windows/system32/
cp ~/opt/wine-adobe/files/share/default_pfx/drive_c/windows/system32/libvkd3d-shader-1.dll \
   ~/.wine_adobe/drive_c/windows/system32/
cp ~/opt/wine-adobe/files/share/default_pfx/drive_c/windows/syswow64/libvkd3d-1.dll \
   ~/.wine_adobe/drive_c/windows/syswow64/
cp ~/opt/wine-adobe/files/share/default_pfx/drive_c/windows/syswow64/libvkd3d-shader-1.dll \
   ~/.wine_adobe/drive_c/windows/syswow64/
```

## 3. Adobe ccd-installer binary is identical across all "different" Adobe direct downloads

Every Adobe direct download stub binary unpacks to the same internal
codebase:

```text
strings <unpacked-stub> | grep ccd-installer
D:\Jenkins\workspace\ccd-installer\develop\build\...
```

Tested binaries (all identical ccd-installer build, only filename differs):

- `Creative_Cloud_Set-Up.exe` (805KB, anon stub from `ccmdl.adobe.com/AdobeProducts/KCCC/1/win32/`)
- `Lightroom_Set-Up_707q.exe` (3.3MB, authenticated Adobe account direct download)
- `Set-up.exe` from CC Desktop 5.10.0.573 ZIP (`ccmdl.adobe.com/AdobeProducts/KCCC/CCD/5_10_0/win64/ACCCx5_10_0_573.zip`)

The per-app "Lightroom" / "Photoshop" download is the same
binary with a query token. All routes through CC Desktop's React UI.

## 4. CEF rendering setup for ccd-installer

ccd-installer ships CEF binaries inside a `.pima` package (which is just
a ZIP archive). It uses dynamic LoadLibrary, not import-time linking, so
`objdump -p Set-up.exe | grep "DLL Name"` doesn't show libcef.dll.

Path to CEF inside the CC Desktop ZIP:

```text
packages/ADC64/CEF64/CEF64.pima (101MB ZIP)
  → libcef.dll, chrome_elf.dll, locales/, resources.pak, icudtl.dat,
    snapshot_blob.bin, v8_context_snapshot.bin, vk_swiftshader.dll,
    vulkan-1.dll
```

These need to be next to `Set-up.exe` for the installer to find CEF.

NOTE: Even with full CEF binaries in place, the installer's React UI
does not render on Wine 10.0 + Hyprland — the blank blue window remains.
The React app appears to load via Wine's MSHTML (which uses xul.dll =
Wine Gecko) rather than CEF, despite CEF being present. The actual UI
asset bundle:

```text
~/.wine_adobe/drive_c/users/steamuser/AppData/Local/Temp/{GUID}/
  index.html (426 bytes — React mount point)
  index.css (940KB)
  CCDInstaller.js (1.3MB — webpacked React app)
```

PhialsBasement's MSHTML patches (Jan 2026) cover JavaScript dispatch
and XML parsing fixes verified against Photoshop 2021/2025 installer
builds. Adobe's ccd-installer React bundle exercises more MSHTML surface
than the patches cover. Result: HTML loads, JS partially executes, no
visible rendered output.

## 5. Useful network endpoint info

CC Desktop / ccd-installer / Lightroom installer all initially contact:

- `cc-api-data.adobe.io:443/ingest` — analytics ping (Dunamis). Fails
  silently in Wine with `HTTP_Status:0 HttpCommunicator error:70`.
  This is NON-FATAL and does not block installer progress.
- `prod-rel-ffc.oobesaas.adobe.com/adobe-ffc-external/core/v1/applications`
  — application catalog. Reached after auth in healthy install.

## 6. Copy-from-Windows path: works through D2D barrier

After installer paths failed, copied LR install directly from mounted
Windows partition `/mnt/windows/Program Files/Adobe/Adobe Lightroom CC/`
to Wine prefix (3.3GB). Process:

1. `rsync -a` LR install dir into prefix `Program Files/Adobe/Adobe Lightroom CC/`
2. Selectively rsync `Common Files/Adobe/` (Desktop Common, OS Extension,
   Keyfiles, Microsoft, Installers, Shell, HelpCfg ~926MB, skipping per-app
   Photoshop/Premiere/Media Encoder dirs)
3. rsync `ProgramData/Adobe/` (2.3GB)
4. rsync user `AppData/Roaming|Local/Adobe` (Lightroom CC, OOBE, AdobeSync,
   CoreSync, NGL, SLData, licflags, CAI)
5. Extract Adobe registry from Windows SOFTWARE hive with `hivex`
   (`hivexml`), Python convert to `.reg`, import via `wine regedit /S`
6. Copy `ndfapi.dll`, `wkscli.dll`, `wdi.dll` from `/mnt/windows/Windows/System32`

Hit: `wdi.dll` requires `ntdll.AlpcMaxAllowedMessageLength` — unimplemented
in Wine 10.0 (and not in 11.8 staging either). Cascading failure: substrate.dll → ndfapi.dll → wdi.dll → unimpl ntdll → status `c0000135`.

**Fix:** built stub `ndfapi.dll` (mingw-w64-gcc) exporting only the three
functions substrate.dll imports (`NdfCloseIncident`, `NdfCreateWebIncident`,
`NdfExecuteDiagnosis`) all returning `S_OK`/`E_NOTIMPL`. Bypasses wdi
entirely. Source + binary at `installers/stubs/`.

Result: `lightroom.exe` and `Adobe Crash Processor.exe` launch. DXVK 2.7.1
Vulkan init succeeds. Lightroom window appears.

## 7. Hard wall: D2D init fails on Wine 10.0

`CreateD2DDeviceResources failed. HResult: 0x88990028`
(`D2DERR_DISPLAY_FORMAT_NOT_SUPPORTED`). D2D tried to create a
device-context on top of D3D11; underlying D3D11/DXGI surface doesn't
support the format combination D2D needs.

Tested approaches that did NOT fix:

- Native `d2d1.dll` from Win11 system32 — fails on unimplemented
  `ext-ms-win-ntuser-uicontext-ext-l1-1-0.dll.2521` (Windows API Set)
- Wine builtin `d2d1.dll` from patched Wine `lib/wine/` — completes load
  but D2D device creation fails inside Wine's d2d1 implementation
- DXVK 2.7.1 d3d11.dll + dxgi.dll + d3d10core.dll override — Vulkan device
  inits successfully, D2D still fails on top

Root cause: Wine's d2d1 implementation has a feature gap around the
D3D11-backed surface formats LR CC's UI rendering pipeline uses. This is
a Wine engine limitation, not a prefix configuration issue. Native Win
d2d1 would work but pulls in Win11 API sets Wine doesn't expose.

WineHQ AppDB has rated LR CC "Garbage" for years specifically for this
barrier. The progress documented in this repo (window paints + Crash
Processor spawns + DXVK Vulkan init succeeds) is further than any public
recipe for current LR CC.

## 8. Wine prefix at `~/.wine_adobe` is a known-good baseline

The prefix is currently configured with:

- Patched Wine 10.0 (PhialsBasement, tag `fix-dropdowns`, 2026-01-26)
- WINEARCH=win64
- Windows 7 compatibility
- winetricks: atmlib, gdiplus, msxml3, msxml6, vcrun2017, vcrun2022,
  corefonts, vkd3d, wininet (native), winhttp (native), dotnet48
- Host: vkd3d, lib32-vkd3d installed via pacman
- libvkd3d-1.dll + libvkd3d-shader-1.dll copied into prefix
- UseXVidMode=N in user.reg

This prefix should be reusable for any non-ccd-installer Adobe app
install path (offline MSI, bundled installer, etc).
