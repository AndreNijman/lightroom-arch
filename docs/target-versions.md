# Target Versions

Research date: 2026-04-28

## Sources Reviewed

- WineHQ Bugzilla search results for Lightroom bugs:
  <https://bugs.winehq.org/buglist.cgi?bug_status=ASSIGNED&bug_status=NEW&bug_status=REOPENED&bug_status=UNCONFIRMED&limit=0&order=short_desc%2Cbug_status%2Ccomponent%2Cproduct+DESC%2Cassigned_to%2Cbug_id+DESC&product=Wine&query_format=advanced>
- Lutris Adobe Lightroom 5 installer:
  <https://lutris.net/games/install/10720/view>
- Lutris Adobe Lightroom game page:
  <https://lutris.net/games/adobe-lightroom-5/>
- Lutris Adobe Creative Cloud page:
  <https://lutris.net/games/adobe-creativecloud/>
- Adobe Lightroom Classic release notes:
  <https://helpx.adobe.com/si/lightroom-classic/help/whats-new/release-notes.html>
- Adobe Lightroom Classic February 2026 feature summary:
  <https://helpx.adobe.com/lightroom-classic/help/whats-new-cc-2015.html>
- The Lightroom Queen Lightroom Classic 15.0 summary:
  <https://www.lightroomqueen.com/whats-new-in-lightroom-2025-10/>
- Reddit thread, "Anyone using lightroom on Linux?", published 2025-07-29:
  <https://www.reddit.com/r/Lightroom/comments/1mcce8g/anyone_using_lightroom_on_linux/>
- Reddit thread, "Will Adobe ever launch a Linux version of Lightroom and Photoshop", published 2025-10-20:
  <https://www.reddit.com/r/Lightroom/comments/1obh087/will_adobe_ever_launch_a_linux_version_of/>
- Reddit thread, "Lightroom Classic - Windows Performance Update", published 2026-04-16:
  <https://www.reddit.com/r/Lightroom/comments/1smrkk4/lightroom_classic_windows_performance_update/>
- Open Wine Components overview for umu/Proton outside Steam:
  <https://openwinecomponents.org/>
- umu-launcher GitHub README:
  <https://github.com/Open-Wine-Components/umu-launcher>
- January 2026 reports on Adobe Creative Cloud / Photoshop Wine patches:
  <https://www.tomshardware.com/software/linux/developer-patches-wine-to-make-photoshop-2021-and-2025-run-on-linux-adobe-creative-cloud-installers-finally-work-thanks-to-html-javascript-and-xml-fixes>
  and <https://linuxiac.com/developer-claims-photoshop-installers-now-work-on-linux-using-wine/>

## Landscape Summary

Public Lightroom-on-Wine evidence is strongest for older perpetual Lightroom releases, especially Lightroom 5.x. The maintained Lutris entry targets Adobe Lightroom 5, creates a 64-bit Wine prefix, sets Windows 7 mode, installs `gdiplus`, `windowscodecs`, and `corefonts`, and notes that an sRGB ICC profile must be copied into the Wine color profile directory.

WineHQ still lists unresolved Lightroom-specific bugs for 4.x, 5.x, 6.x, and 7.5-era builds. The most relevant blockers are image display defects: cropped previews, invisible vertical images with EXIF orientation, partially invisible images at 1:1 magnification, and older menu/scrollbar rendering bugs.

Current Adobe Lightroom Classic releases are in the 15.x line. Adobe's release notes list 15.0 in October 2025, 15.1 in December 2025, 15.1.1 in January 2026, 15.2 in February 2026, and community/Adobe posts reference 15.3 in April 2026. These current builds depend on Creative Cloud installation and activation workflows, where public Wine support is still experimental and mostly discussed through Photoshop/Creative Cloud patch work rather than Lightroom-specific recipes.

No maintained Bottles recipe or ProtonDB entry was found for Lightroom Classic. Bottles remains a plausible front-end for a Wine prefix, but there is not enough public evidence to treat it as the primary path. Proton/umu is useful for running Windows applications inside Proton's expected runtime outside Steam, but the public evidence is gaming-focused and not Lightroom-specific.

## Version Matrix

| Version family | Public success signal | Known blockers | Assessment |
| --- | --- | --- | --- |
| Lightroom 5.x | Highest. Lutris has a concrete installer and multiple historical Wine/PlayOnLinux reports. A July 2025 Reddit comment also reports Lightroom 5 via CrossOver. | Requires old installer media/license, sRGB ICC profile workaround, `gdiplus`, `windowscodecs`, `corefonts`, possible UI glitches. | Primary target for v0.1.0. |
| Lightroom 6.x / 6.14 | Mixed. Last perpetual generation and easier to reason about than Creative Cloud, but WineHQ lists image rendering bugs for 6.0+. | Cropped previews, invisible vertical EXIF-oriented images, partially invisible 1:1 magnification, stale installer availability. | Fallback target if 5.x is unavailable or unacceptable. |
| Lightroom Classic 7.x-11.x | Weak but plausible. WineHQ bug reports include 7.5-era rendering issues; older community notes mention copying an installed Windows application directory into Wine. | Creative Cloud activation, missing DLLs, image rendering bugs, catalog path constraints, GPU acceleration uncertainty. | Experimental fallback only. |
| Lightroom Classic 14.x-15.x | Current product line, but no maintained Lightroom-specific Wine recipe was found. Adobe CC/Photoshop Wine patch work from January 2026 may help installers, but Lightroom remains unproven. | Adobe Creative Cloud installer, authentication, MSHTML/MSXML-style installer issues, .NET/runtime components, GPU acceleration, Windows performance regressions in 15.x even on native Windows. | Research target, not v0.1.0 default. |

## Blockers By Area

### Adobe Creative Cloud Installer

Creative Cloud is the largest blocker for current subscription builds. Recent Wine work around Photoshop 2021/2025 suggests parts of the Adobe installer stack are improving, especially HTML, JavaScript, and XML behavior, but public reports are not yet enough to declare current Lightroom Classic installable on clean Arch via Wine.

### .NET And Runtime Dependencies

Older Lightroom installers usually need Wine components such as `gdiplus`, `windowscodecs`, and fonts. Current Creative Cloud flows may also need additional Microsoft runtimes, but the exact set is not stable enough to encode as a default without real install logs.

### GPU Acceleration

Lightroom Classic's Develop module and newer AI features rely heavily on GPU paths. WineHQ Lightroom bugs indicate image display defects independent of raw GPU performance, and Adobe/Reddit Windows-side threads in 2026 show that native Windows performance in 15.x has also been turbulent. The installer should default to conservative GPU settings and document hardware/vendor details in result files.

## Primary And Fallback Targets

Primary target: Adobe Photoshop Lightroom 5.7.1 / Lightroom 5.x 64-bit through the Lutris-style Wine recipe.

Fallback target: Adobe Lightroom 6.14 standalone, with explicit warnings about WineHQ image-rendering bugs.

Research-only target: Lightroom Classic 15.x through Creative Cloud, Proton/umu, or a copied Windows installation. This target should not block v0.1.0 unless a clean, legal, reproducible install path is proven.

