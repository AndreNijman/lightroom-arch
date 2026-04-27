# Lutris Approach Results

Status: dry-run implementation passes; real GUI validation is blocked until a licensed Lightroom installer and Docker-capable/container-capable test host are available.

## Environment

- Host distro: Arch Linux
- GPU detected by preflight: AMD, Mesa
- AUR helper detected by preflight: yay
- Wine command detected by preflight: present
- Container runtime: Docker not installed in this environment

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
Docker is required for the Arch container smoke test.
```

## Criteria

| Criterion | Result | Notes |
| --- | --- | --- |
| Dry-run install flow | Pass | `tests/smoke.sh --dry-run` exits 0 and asserts expected log lines. |
| Arch container dry-run smoke | Blocked | Docker is not installed on this host. |
| Launches and idles for at least 2 minutes | Not tested | Requires licensed installer and GUI VM. |
| Imports RAW | Not tested | Use `$LR_TEST_RAW` or CC0 fixture. |
| Develop exposure/contrast feedback under 2 seconds | Not tested | Requires GPU-capable GUI validation. |
| Exports JPEG verified by `file` and `identify` | Not tested | Requires real install. |

## Screenshots

Expected path: `docs/screenshots/lutris/`.
