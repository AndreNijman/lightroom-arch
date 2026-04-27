# Lutris Approach Results

Status: container dry-run passes; real install validation pending.

## Environment

- Host distro: Arch Linux
- GPU detected by preflight: AMD, Mesa
- AUR helper detected by preflight: yay
- Wine command detected by preflight: present
- Wine package: `wine-staging 11.7-1`
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
scripts/install.sh --approach lutris --version 5.7.1 --installer /path/to/Lightroom_5.7.1.exe
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

## Criteria

| Criterion | Result | Notes |
| --- | --- | --- |
| Dry-run install flow | Pass | `tests/smoke.sh --dry-run` exits 0 and asserts expected log lines. |
| Arch container dry-run smoke | Pass | Docker installed; `tests/container/run.sh` exits 0. |
| Launches and idles for at least 2 minutes | Not tested | Requires licensed installer and GUI VM. |
| Imports RAW | Not tested | Use `$LR_TEST_RAW` or CC0 fixture. |
| Develop exposure/contrast feedback under 2 seconds | Not tested | Requires GPU-capable GUI validation. |
| Exports JPEG verified by `file` and `identify` | Not tested | Requires real install. |

## Screenshots

Expected path: `docs/screenshots/lutris/`.
