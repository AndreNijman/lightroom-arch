# Attempt 2: PhialsBasement Patched Wine Approach

Research date: 2026-05-15

## Background

All four approaches tested on 2026-04-28 failed because the Adobe Creative
Cloud installer depends on MSHTML and MSXML3 — Windows subsystems for HTML/JS
rendering and XML config parsing. Standard Wine couldn't handle Adobe's data
processing methods on these libraries, causing installations to freeze or abort.

## What changed

In January 2026, developer "PhialsBasement" published Wine patches that fix
the MSHTML/MSXML3 compatibility issues. The patches:

- Wrap data in CDATA to bypass strict XML parsing on Linux
- Correct Wine's ID handling so calls reach the OS properly
- Emulate Internet Explorer 9-style behavior (what Adobe CC installers expect)
- Fix JavaScript dispatch, event handling, and XML parsing

Source: <https://github.com/PhialsBasement/wine-adobe-installers>

Upstream MRs:
- <https://gitlab.winehq.org/wine/wine/-/merge_requests/9970>
- <https://gitlab.winehq.org/wine/wine/-/merge_requests/10025>

Valve Wine PR: <https://github.com/ValveSoftware/wine/pull/310>

## Confirmed working

- Adobe Creative Cloud installer runs to completion
- Photoshop 2021: "buttery smooth" per developer
- Photoshop 2025: functional, some users report issues
- Lightroom Classic: listed as "unstable" in fr0stb1rd guide, but installer works

## Our approach

1. Download pre-compiled patched Wine from PhialsBasement releases (tag: fix-dropdowns, Jan 26 2026)
2. Set up clean win64 prefix at `~/.wine_adobe`
3. Install winetricks deps: atmlib gdiplus msxml3 msxml6 vcrun2017 vkd3d corefonts
4. Download official Adobe Creative Cloud setup.exe
5. Run CC installer through patched Wine
6. Login with active CC subscription
7. Install Lightroom Classic from CC desktop app

## Key references

- PhialsBasement releases: <https://github.com/PhialsBasement/wine-adobe-installers/releases>
- fr0stb1rd guide: <https://fr0stb1rd.gitlab.io/posts/installing-photoshop-2025-on-linux-wine-steam/>
- Tom's Hardware coverage: <https://www.tomshardware.com/software/linux/developer-patches-wine-to-make-photoshop-2021-and-2025-run-on-linux-adobe-creative-cloud-installers-finally-work-thanks-to-html-javascript-and-xml-fixes>
- Phoronix: <https://www.phoronix.com/news/Adobe-Photoshop-2025-Wine-Patch>

## System

- Arch Linux, kernel 7.0.5
- Wine Staging 11.8 (system, not used for this attempt)
- Patched Wine from PhialsBasement fix-dropdowns release
- Active Adobe CC subscription
