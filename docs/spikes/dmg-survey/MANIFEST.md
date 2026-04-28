# DMG Survey Manifest

Repository artifacts:

- `00-setup.txt` - setup, branch, workspace, and tool availability log
- `01-surface.txt` - acquisition notes and pre-extraction DMG inspection
- `02-extracted-tree.txt` - extraction summary, tree sample, file count, extracted size
- `03-binaries.txt` - file type inventory and Mach-O/bundle counts
- `04-electron.txt` - Electron/Node packaging search
- `05-cross-platform.txt` - Java/Python/Lua/HTML/JS runtime survey
- `06-main-executable.txt` - Mach-O dependency analysis with `llvm-otool -L`
- `07-misc.txt` - embedded archive, JSX, license, config, helper, and URL-string survey
- `REPORT.md` - final written verdict

Temporary artifacts:

- Retained: `/tmp/dmg-survey/source.dmg`
- Removed after report: `/tmp/dmg-survey/extracted`

Source DMG:

- Original path: `/home/andre/Downloads/Lightroom/Lightroom_Installer.dmg`
- Working copy: `/tmp/dmg-survey/source.dmg`
- Size: 2,442,063 bytes
- SHA256: `dd86c30c8cdc6600bfdffd47e8cd82282c11e97db2b49e35c9e6c92d89d92b90`
