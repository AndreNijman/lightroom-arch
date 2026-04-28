# Bottles CC Cloud Results

Status: in progress.

## Timing Log

| Phase | Started | Ended | Budget | Outcome |
| --- | --- | --- | --- | --- |
| Phase 0: Branch setup | 2026-04-28T09:05:00+08:00 | 2026-04-28T09:08:02+08:00 | 20 min | Scaffolded Bottles approach from `main`; Flatpak preferred and native Bottles retained only as fallback context. |

## Target

- Product: Adobe Lightroom cloud through Adobe Creative Cloud desktop.
- Not in scope: Lightroom Classic, Lightroom 6 standalone.
- Installer source: `/home/andre/Downloads/Lightroom/Lightroom_Set-Up_707q.exe`
- Test fixture source: `/home/andre/Pictures/test-raws/`
- Bottles distribution: Flatpak preferred via `com.usebottles.bottles`; native/AUR Bottles only as fallback if Flatpak is unavailable.
- Expected Lightroom executable: `~/.var/app/com.usebottles.bottles/data/bottles/bottles/LightroomCCCloud/drive_c/Program Files/Adobe/Adobe Lightroom/Lightroom.exe`
