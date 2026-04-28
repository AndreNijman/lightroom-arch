# Bottles CC Cloud Research

Date: 2026-04-28

## Scope

Target product is Adobe Lightroom cloud installed through Adobe Creative Cloud desktop. Lightroom Classic and Lightroom 6 reports are excluded because their installer, activation, and runtime paths are different.

## Sources Checked

- Bottles runner documentation: <https://docs.usebottles.com/components/runners>
- Bottles environment documentation: <https://docs.usebottles.com/getting-started/environments>
- Bottles dependency manager documentation: <https://docs.usebottles.com/bottles/dependencies>
- Bottles first-run documentation: <https://docs.usebottles.com/getting-started/first-run>
- Bottles issue requesting Adobe Creative Cloud support: <https://github.com/bottlesdevs/Bottles/issues/717>
- Recent Adobe CC on Wine thread: <https://www.reddit.com/r/linux_gaming/comments/1qdgd73/i_made_adobe_cc_installers_work_on_linux_pr_in/>
- Adjacent Photoshop/Bottles forum report: <https://forum.mattkc.com/viewtopic.php?start=20&t=336>
- Bottles Soda runner background: <https://www.gamingonlinux.com/2022/07/wine-manager-bottles-default-runner-now-based-on-valves-wine-fork-and-proton/>

## Findings

No credible Lightroom-cloud-specific Bottles success report was found. The closest current evidence is for Adobe Creative Cloud and Photoshop, not Lightroom cloud. That matters: this branch is testing whether Bottles runners/dependencies improve the Creative Cloud bootstrapper stage that blocked the Wine branch, not validating an already-known Lightroom path.

Bottles supports multiple runners. Its documentation describes Caffe as the official Bottles runner with additional patches, Lutris and Proton-GE as alternate runners, and Vaniglia as the cleaner vanilla-style runner. Bottles documentation recommends Proton only for special cases where a Proton-specific game patch is needed, so Proton-GE is not the first choice for a productivity application.

Bottles' Application environment is the requested environment for this branch. Its docs describe it as aimed at office/productivity and multimedia applications and installing basic fonts and Wine Mono. The dependency manager supports the dependency classes we need: Visual C++ redistributables, .NET 4.8, MSXML, d3dcompiler, and font packages. The docs warn that installing multiple dependencies at once is not recommended because it can cause installation problems, so attempts should install dependencies one at a time.

The older Bottles Adobe request confirms community demand but does not provide a working Creative Cloud recipe. The recent Wine-side Adobe CC thread is more actionable: it reports Creative Cloud installer progress only with a custom patched Wine build and calls out `SetThreadpoolTimerEx` and WebAuthenticationCoreManager/OAuth problems. It also suggests WebView2 plus `ie8`, `msxml3`, `vcrun2012`, `corefonts`, and DLL/profile overrides. That is not Bottles-specific, but it defines likely blockers after the bootstrapper.

Adjacent Photoshop/Bottles reports favor `caffe-9.7` and Bottles Flatpak paths for Adobe Photoshop 2023/2024 workflows. Those reports generally rely on copied Windows installs or app-specific Photoshop setup, not a full Creative Cloud bootstrapper path. They are useful for runner selection, not proof that Creative Cloud desktop installs cleanly.

## Runner Choice

Primary runner: `caffe`.

Rationale: Caffe is the official Bottles Wine runner, Adobe-adjacent Bottles reports mention Caffe, and the target is a productivity application rather than a Steam/game workload. This is the closest match to the branch hypothesis that a Bottles-maintained Wine runner may carry patches or runtime integration missing from system Wine.

Fallback runner: `soda`.

Rationale: Soda is Bottles' Proton-derived/default runner lineage and includes Valve/TKG/GE-oriented patch flow per public Bottles release coverage. It is less semantically appropriate for a productivity app, but it is the best single fallback for launcher/browser/runtime behavior without pivoting into unrelated vanilla Wine.

Not selected: `vaniglia`, because it is intentionally close to vanilla/staging and is less likely to improve on the previous Wine branch. Not selected as initial runner: Proton-GE, because Bottles documentation frames Proton as special-case/gaming-oriented.

## Dependencies

Default dependencies for attempt 1:

- `corefonts`
- `vcredist2019`
- `dotnet48`

Additional Adobe-specific dependencies for attempt 2 if attempt 1 reaches the same blocker:

- `msxml3`
- `vcredist2012`
- `d3dcompiler_47`
- WebView2 bootstrapper if available through Bottles dependency manager or installable inside the bottle

## Known Blockers by Phase

| Phase | Likely blocker |
| --- | --- |
| Bootstrapper | Embedded IE/MSHTML/JScript path, missing WebView2, unsupported `chrome=1` document mode, missing MSXML, `SetThreadpoolTimerEx` in newer Wine paths |
| Creative Cloud launch | Blank window or crash loop in Chromium/CEF shell; potential `SetThreadpoolTimerEx` or Windows Web Authentication APIs |
| Login | OAuth may require Windows WebAuthenticationCoreManager or external browser redirect handling |
| Lightroom install | Creative Cloud may not list subscription apps, may fail downloads, or may need Adobe background services |
| Lightroom launch | Forced sign-in, GPU/CEF instability, subscription validation |
| Criteria | Cloud import/export flow may force sync and may not support local-only import in this runtime |
