# Wine CC Cloud Results

Status: in progress.

## Timing Log

| Phase | Started | Ended | Budget | Outcome |
| --- | --- | --- | --- | --- |
| Phase 0: Branch setup | 2026-04-28T08:28:29+08:00 | 2026-04-28T08:28:29+08:00 | 15 min | Scaffolded from `main`; prerequisites checked. |
| Phase 1: Research | 2026-04-28T08:28:30+08:00 | 2026-04-28T08:30:44+08:00 | 30 min | No Lightroom-cloud-specific Wine success report found; Adobe CC/Photoshop evidence only. |
| Phase 2 attempt 1: bare Wine + bootstrapper | 2026-04-28T08:31:00+08:00 | 2026-04-28T08:32:59+08:00 | 2 hr phase budget | Failed. Bootstrapper produced Adobe OOBE/dunamis state only; no Creative Cloud app and no Lightroom executable. |
| Phase 2 attempt 2: corefonts vcrun2019 dotnet48 + bootstrapper | 2026-04-28T08:33:28+08:00 | 2026-04-28T08:45:29+08:00 | 2 hr phase budget | Failed. Dependencies installed, but bootstrapper hit the same MSHTML/JScript failure and produced no Creative Cloud or Lightroom executable. |
| Phase 2 attempt 3: add mshtml jscript ie8 + bootstrapper | 2026-04-28T08:46:40+08:00 | 2026-04-28T08:59:42+08:00 | 2 hr phase budget | Failed. Current winetricks does not provide `mshtml`; bootstrapper again hit the same MSHTML/JScript failure and produced no Creative Cloud or Lightroom executable. |

## Target

- Product: Adobe Lightroom cloud through Adobe Creative Cloud desktop.
- Not in scope: Lightroom Classic, Lightroom 6 standalone.
- Prefix: `~/.wine-lightroom-cc`
- Expected executable: `~/.wine-lightroom-cc/drive_c/Program Files/Adobe/Adobe Lightroom/Lightroom.exe`

## Phase 2: CC Bootstrapper Install

### Attempt 1: Bare Wine + Bootstrapper

Command:

```sh
rm -rf /home/andre/.wine-lightroom-cc
LIGHTROOM_ARCH_LOG_PATH=/home/andre/.local/state/lightroom-arch/cc-cloud-phase2-1-install.log \
  scripts/install.sh --approach wine-cc-cloud --version cc-cloud \
  --installer /home/andre/Downloads/Lightroom/Lightroom_Set-Up_707q.exe \
  2>&1 | tee /home/andre/.local/state/lightroom-arch/cc-cloud-phase2-1.log
```

Outcome: failed. The bootstrapper reached Wine's IE/MSHTML stack, created only Adobe OOBE/dunamis state, and did not install Creative Cloud desktop.

Relevant log excerpt:

```text
[INFO] run: env WINEPREFIX=/home/andre/.wine-lightroom-cc wine /home/andre/Downloads/Lightroom/Lightroom_Set-Up_707q.exe
017c:fixme:mshtml:process_meta_element Unsupported document mode L"chrome=1"
017c:fixme:jscript:JScriptProperty_SetProperty Unimplemented property 70000001
017c:fixme:jscript:JScriptProperty_SetProperty Unimplemented property 70000002
017c:fixme:mshtml:ActiveScriptSite_OnScriptError
```

Observed prefix artifacts:

```text
drive_c/users/andre/AppData/Roaming/com.adobe.dunamis
drive_c/users/andre/AppData/Local/Adobe/OOBE
```

### Attempt 2: corefonts, vcrun2019, dotnet48 + Bootstrapper

Command:

```sh
rm -rf /home/andre/.wine-lightroom-cc
WINEPREFIX=/home/andre/.wine-lightroom-cc WINEARCH=win64 wineboot --init
WINEPREFIX=/home/andre/.wine-lightroom-cc winetricks -q corefonts vcrun2019 dotnet48
LIGHTROOM_ARCH_LOG_PATH=/home/andre/.local/state/lightroom-arch/cc-cloud-phase2-2-install.log \
  scripts/install.sh --approach wine-cc-cloud --version cc-cloud \
  --installer /home/andre/Downloads/Lightroom/Lightroom_Set-Up_707q.exe \
  2>&1 | tee /home/andre/.local/state/lightroom-arch/cc-cloud-phase2-2.log
```

Outcome: failed. `corefonts`, `vcrun2019`, and `dotnet48` installed into the fresh prefix, but the Adobe bootstrapper still entered Wine's IE/MSHTML stack and failed with the same unsupported document mode and JScript property errors as attempt 1. No Adobe GUI was visible in Hyprland, and the only Adobe paths on disk were temp/OOBE/dunamis state. The process was stopped after no Creative Cloud executable appeared and the hard post-install Lightroom executable verification failed.

Relevant log excerpt:

```text
020c:fixme:mshtml:process_meta_element Unsupported document mode L"chrome=1"
020c:fixme:jscript:JScriptProperty_SetProperty Unimplemented property 70000001
020c:fixme:jscript:JScriptProperty_SetProperty Unimplemented property 70000002
020c:fixme:mshtml:ActiveScriptSite_OnScriptError (0343E948)->(03446560)
[ERROR] Lightroom cloud executable not found after install: /home/andre/.wine-lightroom-cc/drive_c/Program Files/Adobe/Adobe Lightroom/Lightroom.exe
```

Observed prefix artifacts:

```text
drive_c/users/andre/AppData/Roaming/com.adobe.dunamis
drive_c/users/andre/AppData/Local/Temp/Adobe
drive_c/users/andre/AppData/Local/Adobe
```

### Attempt 3: add mshtml, jscript, ie8 + Bootstrapper

Command:

```sh
rm -rf /home/andre/.wine-lightroom-cc
WINEPREFIX=/home/andre/.wine-lightroom-cc WINEARCH=win64 wineboot --init
WINEPREFIX=/home/andre/.wine-lightroom-cc winetricks -q corefonts vcrun2019 dotnet48 mshtml jscript ie8
LIGHTROOM_ARCH_LOG_PATH=/home/andre/.local/state/lightroom-arch/cc-cloud-phase2-3-install.log \
  scripts/install.sh --approach wine-cc-cloud --version cc-cloud \
  --installer /home/andre/Downloads/Lightroom/Lightroom_Set-Up_707q.exe \
  2>&1 | tee /home/andre/.local/state/lightroom-arch/cc-cloud-phase2-3.log
```

Outcome: failed. The intended browser-stack workaround could not be applied as written because `winetricks 20260125` reports `Unknown arg mshtml`. The wrapper still continued into the bootstrapper after dependency setup, and the bootstrapper reproduced the same Wine IE/MSHTML and JScript failure signature. No Adobe GUI was visible and no Creative Cloud or Lightroom executable was installed.

Relevant log excerpt:

```text
Unknown arg mshtml
0148:fixme:mshtml:process_meta_element Unsupported document mode L"chrome=1"
0148:fixme:jscript:JScriptProperty_SetProperty Unimplemented property 70000001
0148:fixme:jscript:JScriptProperty_SetProperty Unimplemented property 70000002
0148:fixme:mshtml:ActiveScriptSite_OnScriptError (0343DC70)->(03445888)
[ERROR] Lightroom cloud executable not found after install: /home/andre/.wine-lightroom-cc/drive_c/Program Files/Adobe/Adobe Lightroom/Lightroom.exe
```

Observed prefix artifacts:

```text
drive_c/users/andre/AppData/Roaming/com.adobe.dunamis
drive_c/users/andre/AppData/Local/Temp/Adobe
drive_c/users/andre/AppData/Local/Adobe
```
