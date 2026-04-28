# Lutris Approach Results

Status: incomplete. Container dry-run passes, but the provided Creative Cloud bootstrapper does not install Lightroom under the Lutris-style Wine prefix.

## Environment

- Host distro: Arch Linux
- Kernel: `Linux ThinkpadL16 6.19.13-arch1-1 #1 SMP PREEMPT_DYNAMIC Tue, 21 Apr 2026 23:38:22 +0000 x86_64 GNU/Linux`
- GPU detected by preflight: AMD, Mesa
- GPU device: `c5:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] HawkPoint1 (rev de)`
- AUR helper detected by preflight: yay
- Wine package: `wine-staging 11.7-1`
- Winetricks package: `winetricks 20260125-1`
- Wine Gecko package: `wine-gecko 2.47.4-2`
- Wine Mono package: `wine-mono 11.0.0-1`
- Lutris package: not installed
- Container runtime: Docker installed and `tests/container/run.sh` passes

## Installer Layout

Source directory: `/home/andre/Downloads/Lightroom`

```text
total 5704
drwxr-xr-x  2 andre andre    4096 Apr 28 07:35 .
drwxr-xr-x 15 andre andre   12288 Apr 28 07:35 ..
-rw-r--r--  1 andre andre 2442063 Apr 28 07:32 Lightroom_Installer.dmg
-rw-r--r--  1 andre andre 3375576 Apr 28 07:35 Lightroom_Set-Up_707q.exe
```

Detected file types:

```text
Lightroom_Installer.dmg:   zlib compressed data
Lightroom_Set-Up_707q.exe: PE32 executable for MS Windows 5.01 (GUI), Intel i386, UPX compressed, 3 sections
```

Checksums:

```text
dd86c30c8cdc6600bfdffd47e8cd82282c11e97db2b49e35c9e6c92d89d92b90  Lightroom_Installer.dmg
9e827ebba742755a31d37811e5e886a6c836a8757d9a4c0404d1633cce7826e2  Lightroom_Set-Up_707q.exe
```

`Lightroom_Set-Up_707q.exe` contains a manifest description of `Creative Cloud Set-up`; it appears to be a Creative Cloud bootstrapper, not an offline Lightroom 5.x installer.

## Exact Commands

Dry-run:

```sh
tests/smoke.sh --dry-run
```

Real install:

```sh
scripts/install.sh --approach lutris --version creative-cloud-bootstrapper --installer /home/andre/Downloads/Lightroom/Lightroom_Set-Up_707q.exe
```

Outer tee log:

```text
/home/andre/.local/state/lightroom-arch/real-install-1777335038.log
```

## Log Excerpts

Dry-run smoke excerpt:

```text
[INFO] install.phase=preflight
[INFO] preflight.os=arch
[INFO] preflight.multilib=enabled
[INFO] preflight.gpu.vendor=amd driver=mesa
[INFO] install.phase=approach approach=lutris
[INFO] approach=lutris version=5.7.1
[INFO] run: env WINEPREFIX=... WINEARCH=win64 wineboot --init
[INFO] run: env WINEPREFIX=... wine reg add HKCU\\Software\\Wine /v Version /d win7 /f
[INFO] run: env WINEPREFIX=... winetricks -q gdiplus windowscodecs corefonts
[INFO] copy: /usr/share/color/icc/colord/sRGB.icc -> .../sRGB ColorSpace Profile.icm
[INFO] smoke.dry_run=passed
```

Container smoke attempt:

```text
tests/container/run.sh
exit 0
```

Real install failure excerpt:

```text
[INFO] preflight.command.wine=present
[INFO] preflight.command.winetricks=present
[INFO] preflight.package.wine-gecko=present
[INFO] preflight.package.wine-mono=present
[INFO] approach=lutris version=creative-cloud-bootstrapper
[INFO] run: env WINEPREFIX=... winetricks -q gdiplus windowscodecs corefonts
gdiplus already installed, skipping
windowscodecs already installed, skipping
corefonts already installed, skipping
[INFO] run: env WINEPREFIX=... wine /home/andre/Downloads/Lightroom/Lightroom_Set-Up_707q.exe
01f4:fixme:mshtml:process_meta_element Unsupported document mode L"chrome=1"
01f4:fixme:jscript:JScriptProperty_SetProperty Unimplemented property 70000001
01f4:fixme:jscript:JScriptProperty_SetProperty Unimplemented property 70000002
01f4:fixme:mshtml:ActiveScriptSite_OnScriptError (03414820)->(0341E888)
[ERROR] Lightroom executable not found after install: /home/andre/.local/share/lightroom-arch/prefixes/lightroom-creative-cloud-bootstrapper/drive_c/Program Files/Adobe/Adobe Photoshop Lightroom/lightroom.exe
```

Post-install prefix inspection found only Adobe bootstrapper state:

```text
drive_c/users/andre/AppData/Roaming/com.adobe.dunamis
drive_c/users/andre/AppData/Local/Adobe/OOBE
```

## Criteria

| Criterion | Result | Notes |
| --- | --- | --- |
| Dry-run install flow | Pass | `tests/smoke.sh --dry-run` exits 0 and asserts expected log lines. |
| Arch container dry-run smoke | Pass | Docker installed; `tests/container/run.sh` exits 0. |
| Launches and idles for at least 2 minutes | Fail | Lightroom was not installed; `lightroom.exe` is absent. |
| Imports RAW | Blocked | Lightroom was not installed. `~/Pictures/test-raws/` is also missing, so no NEF fixture is available. |
| Develop exposure/contrast feedback under 2 seconds | Blocked | Lightroom was not installed. |
| Exports JPEG verified by `file` and `identify` | Blocked | Lightroom was not installed. |

## Screenshots

- `docs/screenshots/lutris/install-creative-cloud-bootstrapper.png`: desktop state during the Creative Cloud bootstrapper run. No Lightroom window was available to capture.

## Known Issues

- The provided Windows installer is a Creative Cloud bootstrapper, not the Lightroom 5.x offline installer this approach targets.
- Wine's MSHTML/JScript path logs unsupported document mode and script-property errors while running the bootstrapper.
- The bootstrapper exits without installing `lightroom.exe`; the script now treats this as a hard failure instead of writing a misleading desktop entry.
- `~/Pictures/test-raws/` is missing, so NEF-based criteria could not be attempted after the install failure.
