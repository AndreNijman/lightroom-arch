# Wine CC Cloud Results

Status: in progress.

## Timing Log

| Phase | Started | Ended | Budget | Outcome |
| --- | --- | --- | --- | --- |
| Phase 0: Branch setup | 2026-04-28T08:28:29+08:00 | 2026-04-28T08:28:29+08:00 | 15 min | Scaffolded from `main`; prerequisites checked. |
| Phase 1: Research | 2026-04-28T08:28:30+08:00 | 2026-04-28T08:30:44+08:00 | 30 min | No Lightroom-cloud-specific Wine success report found; Adobe CC/Photoshop evidence only. |
| Phase 2 attempt 1: bare Wine + bootstrapper | 2026-04-28T08:31:00+08:00 | 2026-04-28T08:32:59+08:00 | 2 hr phase budget | Failed. Bootstrapper produced Adobe OOBE/dunamis state only; no Creative Cloud app and no Lightroom executable. |

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
