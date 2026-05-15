# Attempt 6: Delay-Load Fix Breaks the Graphics Wall — WebView2 Is Next

## Summary

The D2D/dwrite graphics-init wall that blocked attempts 1-5 is **solved**.
Lightroom Classic 9.3.1 now boots past graphics init, renders fonts and
D3D11 textures, reaches its version banner and networking/licensing
stage. New blocker: missing WebView2 runtime.

## The full-Wine-rebuild dead end

Attempt 5 rebuilt all of PhialsBasement Wine 10.0 with
`--enable-archs=i386,x86_64` (WoW64 single-tree). Result: a systemically
broken Wine — every process crashed at a constant address
`0x6fffffc05370`, all Winedevice services failed. The bundled Wine ships
separate `wine`+`wine64` (traditional dual build); the WoW64 single-tree
config is incompatible with the PhialsBasement proton patches. **Do not
rebuild Wine WoW64-style.** The build burned hours and produced nothing
usable. Reverted to bundled Wine.

## Root cause of the dwrite crash

Attempt 4 blamed a dwrite *delay-load* crash and guessed mingw ABI
mismatch. Diagnosis via `minidump_stackwalk` on the Adobe crash dump
nailed it:

```
Crash reason: EXCEPTION_ACCESS_VIOLATION_WRITE
Crash address: 0x6ffffd57a3c0   (just past end of d2d1.dll image)
 0  ntdll.dll + 0x1518f          (memcpy/memmove store)
 2  DWrite.dll + 0xe72a0
 3  d2d1.dll  + ...
 7  d2d1.dll  + 0x268b           (__delayLoadHelper2)
```

The fault is a **write past the end of d2d1.dll's image**. Our patched
`d2d1.dll` (rebuilt with mingw-w64-gcc 16.1.0) has a delay-import
descriptor / IAT layout that the bundled Wine loader's
`__delayLoadHelper2` interprets wrongly — the helper writes the resolved
import address to an offset past d2d1's mapped image and faults.

The crash address stayed at `ntdll +1518F` whether dwrite was builtin or
native — proving **dwrite was never the cause**. The delay-load helper
itself is the bug.

## The fix: non-delay imports

`dlls/d2d1/Makefile.in`:

```
-IMPORTS   = d3d10_1 dxguid uuid gdi32 user32 advapi32 d3dcompiler
-DELAYIMPORTS = dwrite xmllite ole32
+IMPORTS   = d3d10_1 dxguid uuid gdi32 user32 advapi32 d3dcompiler dwrite xmllite ole32
+DELAYIMPORTS =
```

Rebuilt `d2d1.dll` — `dwrite`, `xmllite`, `ole32` are now normal imports
resolved by Wine's PE loader at load time. No delay-load helper, no
runtime IAT patching, no broken thunk. Installed into bundled Wine
(`~/opt/wine-adobe/files/lib/wine/x86_64-windows/d2d1.dll`) and the
prefix.

## dwrite: builtin, not native

- Native Windows `DWrite.dll` under Wine → infinite exception recursion
  → `err:virtual:virtual_setup_exception stack overflow`. Native dwrite
  depends on Windows internals Wine doesn't replicate.
- Wine builtin `dwrite.dll` as a *normal* import of the non-delay
  d2d1.dll → works. Launch with `WINEDLLOVERRIDES=...;dwrite=b`.

## Current state — graphics wall broken

With non-delay `d2d1.dll` + builtin `dwrite`, LR Classic 9.3.1:
- Boots past D2D + dwrite init (no crash)
- DXVK 2.7.1 initializes, finds AMD Radeon 780M via Vulkan
- Renders fonts (`dwritefontface5` calls) and D3D11 textures
- Prints version banner, runs networking/licensing code

## Next blocker: WebView2

LR then crashes:

```
WebView2: Failed to find an installed WebView2 runtime
...
EXCEPTION_ACCESS_VIOLATION addr=0x14028231C  (lightroom.exe code)
```

LR can't find the Microsoft Edge WebView2 runtime, then its
WebView2-handling code dereferences a null/invalid pointer and faults.
LR Classic needs WebView2 for its account/login UI.

Fix in progress: copy the WebView2 Evergreen runtime (148.0.3967.54)
from the Windows partition into the prefix and point LR at it via
`WEBVIEW2_BROWSER_EXECUTABLE_FOLDER`. This is a Chromium-under-Wine
problem and may not work cleanly.

## Launch command (current best)

```bash
cd "$WINEPREFIX/drive_c/Program Files/Adobe/Adobe Lightroom CC"
WINEPREFIX=~/.wine_adobe \
WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d;dwrite=b" \
~/opt/wine-adobe/files/bin/wine lightroom.exe
```
