# Upstream Blockers

Research date: 2026-04-28

This file records the upstream conditions that make the tested Lightroom-on-Wine approaches non-shippable on Arch Linux in April 2026.

## Adobe ended Lightroom 6.14 distribution on 2023-12-31.

Adobe's Lightroom 6 end-of-support page says Lightroom 6 download support ended on 2023-12-31 and that Lightroom 6.14 cannot be downloaded from Adobe after that date:

<https://helpx.adobe.com/lightroom-classic/help/lightroom-6-end-of-support.html>

That removes the only practical legal input for a clean Lightroom 6.14 installer workflow. The Lutris approach was intended for old perpetual Lightroom media, but the provided installer during validation was a Creative Cloud bootstrapper, not a Lightroom 6.14 offline installer.

The ProDesignTools Lightroom 6 direct links also route to Adobe-hosted `prdl-download.adobe.com` payloads. Those direct download payloads return HTTP 403 as of 2026-04-28, matching Adobe's published end of download availability.

## winetricks 20260125 removed the mshtml verb.

The vanilla Wine Creative Cloud attempt followed the usual browser-stack workaround path: `corefonts`, `vcrun2019`, `dotnet48`, then `mshtml`, `jscript`, and `ie8`. On the tested Arch system, `winetricks 20260125` rejected that path:

```text
Unknown arg mshtml
```

Microsoft has pulled the Internet Explorer 8 redistributable that older Wine recipes depended on. Without that redistributable, the `mshtml` verb has no recoverable path in current winetricks. The Adobe Creative Cloud bootstrapper still enters Wine's IE/MSHTML/JScript code path, but the dependency chain that older recipes used to satisfy it is no longer available.
