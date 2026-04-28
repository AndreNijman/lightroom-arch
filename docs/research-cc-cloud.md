# Adobe Lightroom Cloud On Wine Research

Research date: 2026-04-28

Target product: Adobe Lightroom cloud, installed through Adobe Creative Cloud desktop. This is not Lightroom Classic and not Lightroom 6.x standalone.

## Sources Reviewed

- Adobe Lightroom supported versions:
  <https://helpx.adobe.com/lightroom-cc/kb/supported-versions.html>
- Adobe Creative Cloud application base versions:
  <https://helpx.adobe.com/enterprise/kb/adobe-cc-app-base-versions.html>
- Lutris Adobe Creative Cloud page:
  <https://lutris.net/games/adobe-creativecloud/>
- Lutris Adobe Creative Cloud latest 64-bit installer script:
  <https://lutris.net/games/install/14525/view>
- Phoronix, "Adobe Photoshop 2025 Installer Now Working On Linux With Patched Wine", 2026-01-16:
  <https://www.phoronix.com/news/Adobe-Photoshop-2025-Wine-Patch>
- Tom's Hardware, "Developer patches Wine to make Photoshop 2021 & 2025 run on Linux", 2026-01-18:
  <https://www.tomshardware.com/software/linux/developer-patches-wine-to-make-photoshop-2021-and-2025-run-on-linux-adobe-creative-cloud-installers-finally-work-thanks-to-html-javascript-and-xml-fixes>
- Linuxiac, "Developer Claims Photoshop Installers Now Work on Linux Using Wine", 2026-01-17:
  <https://linuxiac.com/developer-claims-photoshop-installers-now-work-on-linux-using-wine/>
- Reddit, "Creative Cloud working on wine 10.15", 2026-01-18:
  <https://www.reddit.com/r/linux_gaming/comments/1qg9wgz/creative_cloud_working_on_wine_1015/>
- Reddit, "Is anyone using the WINE Adobe Installers for Premiere Pro?", 2026-04-02:
  <https://www.reddit.com/r/linuxquestions/comments/1savdwb/is_anyone_using_the_wine_adobe_installers_for/>
- Reddit, "On FOSS alternatives vs WINE + Lightroom", 2026-02-04:
  <https://www.reddit.com/r/FOSSPhotography/comments/1qvy3e0/on_foss_alternatives_vs_wine_lightroom/>

## Current Product State

Adobe lists Lightroom cloud as an installable Creative Cloud desktop app. Adobe's enterprise base-version table lists Lightroom sap code `LRCC`, base version `9.2`, and platform `Win64` for the current generation. This confirms the correct Windows target is a 64-bit Creative Cloud application, not the older standalone Lightroom installer path.

## Public Wine Evidence

No reliable public report was found showing Lightroom cloud installed, launched, signed in, imported RAW files, edited, and exported through Wine.

The strongest adjacent evidence is for Adobe Creative Cloud and Photoshop:

- January 2026 reports describe patched Wine work for Adobe Creative Cloud installers and Photoshop 2021/2025.
- The repeatedly cited blockers are Wine `mshtml` and `msxml3` behavior, especially HTML/JavaScript/XML behavior used by Adobe installer UIs.
- Community claims mention Creative Cloud working on Wine 10.15 with the `ie8` winetricks verb, but the public evidence is not Lightroom-cloud-specific.
- Lutris has a Creative Cloud installer recipe targeting win64 and the Creative Cloud desktop executable, but it is old, warns that latest 64-bit is "Not Working Properly", and says Photoshop 2022 and below are the current support boundary.

## Best Known Starting Point

- Wine runner: newest available Wine Staging first; if blocked, test a patched Wine / Valve Wine / Proton-GE lineage that includes the 2026 Adobe MSHTML/MSXML changes.
- Prefix architecture: `win64`.
- Windows version: start bare for attempt 1, then test `win10`.
- Expected Creative Cloud desktop executable:
  `~/.wine-lightroom-cc/drive_c/Program Files/Adobe/Adobe Creative Cloud/ACC/Creative Cloud.exe`
- Expected Lightroom cloud executable:
  `~/.wine-lightroom-cc/drive_c/Program Files/Adobe/Adobe Lightroom/Lightroom.exe`

## Candidate Winetricks Verbs

Strict ordered experiment list for this branch:

1. Bare Wine + bootstrapper.
2. `corefonts vcrun2019 dotnet48`.
3. `mshtml jscript ie8`.
4. Wine Staging or Lutris-GE/Proton runner switch.
5. Windows version set to `win10`.
6. Specific DLL overrides only when justified by logs.

Lutris' older Creative Cloud recipe also used a larger set:
`fontsmooth=rgb gdiplus vcrun2008 vcrun2010 vcrun2012 vcrun2013 vcrun2015 vcrun2017 atmlib msxml6 corefonts msls31 riched20 tahoma dxvk vkd3d win10`.
That list is useful background, but this branch should follow the narrower ordered workaround plan to avoid undebuggable changes.

## Known Blockers By Phase

| Phase | Likely blocker |
| --- | --- |
| Bootstrapper | MSHTML/JScript/DOM event handling, MSXML parsing, installer UI blank or exits early. |
| Creative Cloud app | Web UI rendering blank, background Adobe services not starting, Adobe IPC broker/service assumptions. |
| Login | Embedded OAuth browser, URL-handler redirect, token handoff between browser and CC desktop. |
| Lightroom install | Creative Cloud product list rendering, download/install entitlement checks, background service dependency. |
| Lightroom launch | Sign-in flow, GPU acceleration, cloud sync, UXP/CEF-style embedded web components. |

## Conclusion

Lightroom cloud on Wine is unproven. The branch should be treated as an experiment against Adobe Creative Cloud infrastructure, not as a small variation of the Lightroom 5/6 Lutris recipe. The most likely hard blocker is the Adobe login and Creative Cloud desktop web UI path, even if the bootstrapper itself installs after Wine MSHTML/MSXML workarounds.

