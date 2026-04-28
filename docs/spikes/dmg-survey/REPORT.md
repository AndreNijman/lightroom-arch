# Lightroom Mac DMG Survey

## What was investigated

The survey inspected a locally cached Lightroom Mac DMG found at `/home/andre/Downloads/Lightroom/Lightroom_Installer.dmg`, copied to `/tmp/dmg-survey/source.dmg` on 2026-04-28T12:40:18+08:00. Per the acquisition rule, this local Lightroom-specific DMG was preferred over downloading Adobe's current Creative Cloud bootstrapper.

- Source URL: N/A; local cached DMG used
- HTTP headers: N/A; no network download performed
- Size: 2,442,063 bytes
- SHA256: `dd86c30c8cdc6600bfdffd47e8cd82282c11e97db2b49e35c9e6c92d89d92b90`
- DMG type: zlib-compressed Apple DMG containing one HFS+ payload
- HFS timestamps shown by 7z: created 2020-10-29, modified 2020-10-30

## What's inside

The DMG is a small Lightroom installer bootstrapper, not the full Lightroom application. Extraction produced a 5.7 MB tree with one `Lightroom Installer.app` bundle, 93 files as seen on Linux after alternate stream extraction, two x86_64 Mach-O executables, no `.framework` directories, no `.dylib` files, and no `.bundle` directories. The app includes a native main executable at `Contents/MacOS/Install`, a privileged helper at `Contents/Library/LaunchServices/com.adobe.acc.installer.v2`, localized strings, images, CSS, and an Angular/jQuery HTML UI. `config.xml` identifies the product as Lightroom (`sapCode` `LRCC`) and lists a `productSize` of `1309135199`, consistent with a downloader/bootstrapper.

## Cross-platform components found

None as standalone runnable components.

The bundle contains HTML/CSS/JavaScript assets:

- `Contents/Resources/main.html`
- `Contents/Resources/js/*.js`
- `Contents/Resources/lib/angular.min.js`
- `Contents/Resources/lib/jquery*.js`

Those files are not an Electron, CEF, Node, Java, Python, Lua, or archive-packaged app. There is no `Electron Framework.framework`, `app.asar`, `electron.asar`, `package.json`, `node_modules`, `.jar`, `.class`, `.py`, `.pyc`, `.lua`, `.jsx`, or `.jsxbin`. The JavaScript calls `window.JSObject.messageFromHtml(...)` through `sendMessageToNative(...)`, which indicates a native WebKit bridge owned by the Mach-O installer. Without that native macOS host and its Apple framework dependencies, the web assets are only UI resources.

## Linked Apple Frameworks

The main executable is `Contents/MacOS/Install`, confirmed as a Mach-O 64-bit x86_64 executable. `llvm-otool -L` shows these Apple system dependencies:

- `ServiceManagement.framework`
- `JavaScriptCore.framework`
- `OpenGL.framework`
- `IOKit.framework`
- `WebKit.framework`
- `Cocoa.framework`
- `SystemConfiguration.framework`
- `Security.framework`
- `Foundation.framework`
- `AppKit.framework`
- `ApplicationServices.framework`
- `CoreFoundation.framework`
- `CoreServices.framework`
- `/usr/lib/libobjc.A.dylib`
- `/usr/lib/libc++.1.dylib`
- `/usr/lib/libSystem.B.dylib`

The helper executable also links only to Apple system frameworks and `/usr/lib` Mach-O runtime libraries. No Adobe-bundled dynamic framework, bundled `.dylib`, or open-source third-party library is linked directly. These Apple frameworks are not substitutable on Linux without a Darling-class macOS compatibility layer.

## Verdict

A. **DMG path is dead — pure Mach-O + Apple frameworks.** Extracting and running any functional part of this on Linux requires a working macOS translation layer (Darling), which doesn't support Adobe CC apps and won't in any reasonable timeframe. Recommendation: same as Wine — close this path, ship 0.1.0, move on.

The only cross-platform-looking material is static HTML/CSS/JavaScript UI content, but it depends on a native WebKit bridge implemented by the Mach-O installer. It is not a separately useful Electron, Java, Node, Python, or CEF component.

## Honest caveats

- This did not disassemble the Mach-O binaries.
- This did not attempt to run, install, mount through macOS tooling, or invoke any extracted binary.
- This did not inspect runtime network responses or Adobe server-side payloads that the bootstrapper would download.
- This did not validate code-signing or integrity beyond observing extracted code-signing resources and helper entitlement strings.
- `dmg2img` was unavailable from configured pacman repositories on this host, so `dmg2img -V` metadata and fallback extraction were skipped. 7z extraction succeeded.
- The investigated DMG was the local cached Lightroom-specific DMG requested by the stop/order rules, not a freshly downloaded Creative Cloud desktop DMG.

## Retention

`/tmp/dmg-survey/source.dmg` was retained for follow-up. `/tmp/dmg-survey/extracted` was removed after the report because it is large throwaway extraction output.
