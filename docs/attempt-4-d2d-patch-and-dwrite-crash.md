# Attempt 4: D2D Patch Unblocks Init, dwrite Delay-Load Crashes Next

## Summary

Patched Wine 10.0 `d2d1.dll` to register `CLSID_D2D1ColorManagement` as a
stub builtin effect. This unblocked the "CreateD2DDeviceResources failed
HResult 0x88990028" error that killed every previous run.

After the patch, `lightroom.exe` boots further:
- D2D factory creates successfully
- Adobe init code runs
- LR prints `OutputDebugStringW L"Lightroom version: 9.3.1 [ 20260429-1653-6cd29ca ] (Apr 29 2026)\n"`
- Then access violation crashes the process

## Crash backtrace

```
dispatch_exception code=c0000005 (EXCEPTION_ACCESS_VIOLATION)
  addr=00006FFFFFF4518F  (ntdll.dll +1518F)
  info[0]=1, info[1]=00006FFFFD57A3C0  (write fault)

virtual_unwind:
  ntdll.dll +1518F
  d2d1.dll +268B   __delayLoadHelper2
  d2d1.dll +1297   __wine_delay_load_dwrite
  d2d1.dll +1A5A8  d2d_device_context_init
  d2d1.dll +E5D1   d2d_d3d_create_render_target
  d2d1.dll +11010  d2d_dc_render_target_init
  d2d1.dll +215CD  d2d_factory_CreateDCRenderTarget
  ui.dll +1229E5   (LR's UI code)
```

## Diagnosis

`d2d_device_context_init()` in `dlls/d2d1/device.c` calls
`DWriteCreateFactory()`. d2d1.dll has dwrite.dll as a delay-loaded
import (linked with `libdwrite.delay.a`). When the delay load triggers,
`__delayLoadHelper2` → `__wine_delay_load_dwrite` runs to fault-in
dwrite.dll, but it dereferences a NULL/invalid pointer inside ntdll
during the load.

This is NOT a ColorManagement effect issue. The patch correctly
registers the effect. The crash is in the dwrite delay-load mechanism.

## Suspected cause

The built d2d1.dll was produced with mingw-w64-gcc 16.1.0; the bundled
PhialsBasement Wine 10.0 binary was built with an older mingw. Possible
ABI mismatch in the delay-load helper thunks. The Wine-side
`__wine_delay_load_dwrite` from the rebuilt DLL may not match the
runtime expectations of Wine's own loader.

## Alternative crash interpretations

- dwrite.dll itself can't load because of a Wine bug
- `delay_imports` resolution generates incorrect IAT in our build
- LR's address space layout puts d2d1 + dwrite at incompatible offsets

## Workaround options (untested)

1. Rebuild Wine d2d1.dll **without** `--with-mingw` — use Wine's own
   internal toolchain to ensure ABI match. Requires rebuilding more of
   Wine to get the proper build deps.
2. Modify `dlls/d2d1/Makefile.in` to link dwrite as a normal (non-delay)
   import. Bypasses delay-load helper entirely.
3. Force `dwrite=native` and copy Windows DWrite.dll into prefix. Native
   doesn't go through Wine's delay-load mechanism.
4. Build full Wine from PhialsBasement source rather than just d2d1.dll
   so the whole chain uses consistent ABI.

## Real status

Genuine breakthrough on the D2D blocker. LR initialization now runs
~10x further than any previous attempt. Hit a new crash, which is
itself a fixable problem (different from the fundamental Wine engine
gap originally suspected).

Still not a working LR. But: confirmed the path is viable with more
Wine patches. Each new crash is closer to running LR.
