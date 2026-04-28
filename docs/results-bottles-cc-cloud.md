# Bottles CC Cloud Results

Status: in progress.

## Timing Log

| Phase | Started | Ended | Budget | Outcome |
| --- | --- | --- | --- | --- |
| Phase 0: Branch setup | 2026-04-28T09:05:00+08:00 | 2026-04-28T09:08:02+08:00 | 20 min | Scaffolded Bottles approach from `main`; Flatpak preferred and native Bottles retained only as fallback context. |
| Phase 1: Research | 2026-04-28T09:08:03+08:00 | 2026-04-28T09:09:45+08:00 | 20 min | Selected `caffe` primary and `soda` fallback; no Lightroom-cloud-specific Bottles success report found. |
| Phase 2 attempt 1: `caffe` default deps | 2026-04-28T09:14:46+08:00 | 2026-04-28T09:50:01+08:00 | 90 min | Bottle and dependencies installed after script fixes; Adobe bootstrapper launched, prompted for Gecko, then hung with no CC Desktop installation. |
| Phase 2 attempt 2a: `caffe` browser deps | 2026-04-28T09:53:58+08:00 | 2026-04-28T10:45:00+08:00 | 90 min | Invalidated by script dependency-order bug: native `wininet` was enabled before `iertutil`, causing Wine to enter `winedbg` while setting the `urlmon` override. |
| Phase 2 attempt 2b: `caffe` browser deps reordered | 2026-04-28T10:46:38+08:00 | 2026-04-28T11:13:02+08:00 | 90 min | Dependencies installed and Adobe bootstrapper launched with WebView2, but no visible window or Creative Cloud install appeared; process looped on WinRT/RPC/OLE errors. |

## Target

- Product: Adobe Lightroom cloud through Adobe Creative Cloud desktop.
- Not in scope: Lightroom Classic, Lightroom 6 standalone.
- Installer source: `/home/andre/Downloads/Lightroom/Lightroom_Set-Up_707q.exe`
- Test fixture source: `/home/andre/Pictures/test-raws/`
- Bottles distribution: Flatpak preferred via `com.usebottles.bottles`; user-scope Flatpak is used because system-scope deployment is not permitted for this user. Native/AUR Bottles only as fallback if Flatpak is unavailable.
- Primary runner: `caffe`
- Fallback runner: `soda`
- Expected Lightroom executable: `~/.var/app/com.usebottles.bottles/data/bottles/bottles/LightroomCCCloud/drive_c/Program Files/Adobe/Adobe Lightroom/Lightroom.exe`

## Phase 2: Bottle Creation And Bootstrapper Install

### Attempt 1: Primary Runner, Default Deps

- Runner: `caffe`, normalized by the script to `caffe-9.7`.
- Components provisioned: `caffe-9.7`, `dxvk-2.7.1`, `vkd3d-proton-3.0`, `dxvk-nvapi-v0.9.1`, `latencyflex-v0.1.1`.
- Dependencies installed through Bottles backend: `arial32`, `times32`, `courie32`, `vcredist2019`, `dotnet48`.
- Log: `~/.local/state/lightroom-arch/bottles-cc-phase2-1.log`.
- Outcome: failed. The Adobe bootstrapper started and wrote WAM/Dunamis logs, but did not install Creative Cloud Desktop or Lightroom.

Commands:

```sh
BOTTLES_CC_RUNNER=caffe \
LIGHTROOM_ARCH_LOG_PATH=/home/andre/.local/state/lightroom-arch/bottles-cc-phase2-1-install.log \
scripts/install.sh --approach bottles-cc-cloud --version cc-cloud --installer /home/andre/Downloads/Lightroom
```

Important observations:

- Bottles CLI runs in forced offline mode, so the first implementation could not fetch managed components. The script now provisions the pinned runner and DLL components before invoking `bottles-cli`.
- `bottles-cli` has no `dependencies` subcommand in Bottles 63.2. The script now invokes Bottles' Python backend dependency manager from inside the Flatpak.
- Flatpak sandboxing blocked the original installer path. The script now stages the installer under `~/.var/app/com.usebottles.bottles/data/bottles/temp/lightroom-arch-installers/`.
- Wine displayed a `Wine Gecko Installer` prompt. The user clicked `Install`; the prompt closed.
- After Gecko completed, no Adobe installer window appeared. The only remaining installer process was `Lightroom_Set-Up_707q.exe`.
- No `Creative Cloud.exe`, `Creative Cloud*.exe`, `ACC*.exe`, or `Lightroom.exe` was found in the bottle.

Representative log excerpts:

```text
dependency=arial32 status=installed
dependency=times32 status=installed
dependency=courie32 status=installed
dependency=vcredist2019 status=installed
dependency=dotnet48 status=installed
[INFO] installer.staged=/home/andre/.var/app/com.usebottles.bottles/data/bottles/temp/lightroom-arch-installers/Lightroom_Set-Up_707q.exe
[INFO] run: bottles_cc::flatpak_env flatpak run --command=bottles-cli com.usebottles.bottles run -b LightroomCCCloud -e /home/andre/.var/app/com.usebottles.bottles/data/bottles/temp/lightroom-arch-installers/Lightroom_Set-Up_707q.exe
01c0:err:kerberos:kerberos_LsaApInitializePackage no Kerberos support, expect problems
020c:err:ole:ifproxy_release_public_refs IRemUnknown_RemRelease failed with error 0x800706be
```

Adobe WAM/Dunamis logs showed the bootstrapper initialized and reached Adobe telemetry:

```text
Application initialized successfully.
HTTP Request Status code 200.
```

Decision for attempt 1: proceed to attempt 2, still on primary runner, with additional Adobe-specific browser/runtime dependencies.

### Attempt 2a: Primary Runner, Browser Deps, Invalid Script Ordering

- Runner: `caffe`, normalized by the script to `caffe-9.7`.
- Bottle: `LightroomCCCloudAttempt2`.
- Dependencies requested through Bottles backend: `arial32`, `times32`, `courie32`, `vcredist2019`, `dotnet48`, `gecko`, `mono`, `wininet`, `urlmon`, `iertutil`, `riched20`, `webview2`.
- Log: `~/.local/state/lightroom-arch/bottles-cc-phase2-2.log`.
- Outcome: invalid attempt. The dependency manager installed `wininet` before `iertutil`; enabling the native `wininet` override caused Wine itself to fail before `iertutil` could be installed.

Representative log excerpt:

```text
Dependency installed: wininet in LightroomCCCloudAttempt2
Installing dependency [urlmon] in bottle [LightroomCCCloudAttempt2].
Copying urlmon.dll to .../drive_c/windows/system32//urlmon.dll
Adding Key: [HKEY_CURRENT_USER\Software\Wine\DllOverrides] with Value: [urlmon] and Data: [native,builtin]
err:module:import_dll Library iertutil.dll (which is needed by L"C:\\windows\\system32\\wininet.dll") not found
err:module:DelayLoadFailureHook failed to delay load wininet.dll.InternetOpenA
wine: Unimplemented function wininet.dll.InternetOpenA called ... starting debugger...
```

Script fix: order browser DLL dependencies so `iertutil` is installed before `wininet` and `urlmon`. Re-run attempt 2 after this fix because the failure did not exercise the Adobe bootstrapper.

### Attempt 2b: Primary Runner, Browser Deps, Reordered

- Runner: `caffe`, normalized by the script to `caffe-9.7`.
- Bottle: `LightroomCCCloudAttempt2b`.
- Dependencies installed through Bottles backend: `arial32`, `times32`, `courie32`, `vcredist2019`, `dotnet48`, `gecko`, `mono`, `iertutil`, `wininet`, `urlmon`, `riched20`, `webview2`.
- Log: `~/.local/state/lightroom-arch/bottles-cc-phase2-2b.log`.
- Outcome: failed. Dependency installation completed and the Adobe bootstrapper launched with WebView2 available, but it did not create a visible installer window or install Creative Cloud Desktop.

Commands:

```sh
BOTTLES_CC_BOTTLE=LightroomCCCloudAttempt2b \
BOTTLES_CC_RUNNER=caffe \
BOTTLES_CC_EXTRA_DEPS=gecko,mono,wininet,urlmon,iertutil,riched20,webview2 \
LIGHTROOM_ARCH_LOG_PATH=/home/andre/.local/state/lightroom-arch/bottles-cc-phase2-2b-install.log \
scripts/install.sh --approach bottles-cc-cloud --version cc-cloud --installer /home/andre/Downloads/Lightroom
```

Important observations:

- The reordered dependency pass succeeded: `iertutil`, `wininet`, `urlmon`, `riched20`, and `webview2` all installed.
- `riched20` required `W2KSP4_EN.EXE`; this was slow but completed.
- `webview2` installed and the bootstrapper spawned `msedgewebview2.exe`, but the WebView2 process became defunct after launch.
- Hyprland had no mapped Wine, Adobe, Bottles, Lightroom, or Creative Cloud window during the attempt.
- The bootstrapper created only Adobe temporary/WAM state under `Temp/CreativeCloud`; no `Creative Cloud.exe`, `ACC*.exe`, or `Lightroom.exe` was found.
- The WAM log reached Adobe telemetry with HTTP 200, then stopped; the process continued emitting WinRT/RPC/OLE errors.

Representative log excerpts:

```text
dependency=iertutil status=installed
dependency=wininet status=installed
dependency=urlmon status=installed
dependency=riched20 status=installed
dependency=webview2 status=installed
[INFO] run: bottles_cc::flatpak_env flatpak run --command=bottles-cli com.usebottles.bottles run -b LightroomCCCloudAttempt2b -e .../Lightroom_Set-Up_707q.exe
0324:err:combase:RoGetActivationFactory Failed to find library for L"Windows.Security.Authentication.Web.Core.WebAuthenticationCoreManager"
0334:err:combase:RoGetActivationFactory Failed to find library for L"Windows.Security.Authentication.Web.Core.WebAuthenticationCoreManager"
0664:err:ole:ifproxy_release_public_refs IRemUnknown_RemRelease failed with error 0x800706be
052c:err:rpc:RpcAssoc_BindConnection rejected bind for reason 0
```

Adobe WAM/Dunamis logs showed initialization and telemetry only:

```text
Application initialized successfully.
HTTP Request Status code 200.
```

Decision for attempt 2: proceed to the single fallback runner attempt. The added browser stack improved dependency coverage but did not get past the Creative Cloud bootstrapper wall.
