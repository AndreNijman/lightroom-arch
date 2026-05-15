# Attempt 5: Full PhialsBasement Wine 10.0 Rebuild From Source

## Why

Attempt 4 patched `d2d1.dll` to register `CLSID_D2D1ColorManagement` and
got LR past the `CreateD2DDeviceResources HResult 0x88990028` wall.
LR boot now reaches the version banner print:

```
Lightroom version: 9.3.1 [ 20260429-1653-6cd29ca ] (Apr 29 2026)
```

But then crashes inside `__wine_delay_load_dwrite` →
`__delayLoadHelper2` → access violation in `ntdll +1518F`.

Hypothesis (from advisor): our patched `d2d1.dll` was rebuilt with the
host system's `mingw-w64-gcc 16.1.0`, while the bundled PhialsBasement
Wine binary was built earlier with an older mingw. The delay-load helper
thunks in the rebuilt DLL may not match the ABI Wine's loader expects.

If true, rebuilding the *whole* Wine tree with the current mingw
(everything consistent at 16.1.0) should resolve the mismatch.

## Plan

1. PhialsBasement source already cloned at `/tmp/wine-src` on branch
   `proton_10.0`, with our d2d1 ColorManagement patch applied to
   `dlls/d2d1/effect.c`. All other tree-dirtying artifacts from previous
   incremental builds reset to clean.
2. Configure with WoW64 single-tree:
   ```
   ../configure \
     --prefix=$HOME/opt/wine-adobe-built \
     --enable-archs=i386,x86_64 \
     --disable-tests
   ```
3. `make -j16` — full 64+32 build in one tree.
4. `make install` into `~/opt/wine-adobe-built/`.
5. Re-launch LR using the new wine binary against the existing
   `~/.wine_adobe` prefix.

## Configure result

- All required deps present.
- Missing optional deps (none needed for LR): libOSMesa, OSSv4,
  libcapi20, libpiper.
- WoW64 build via `--enable-archs=i386,x86_64`.

## Expected outcome

- `d2d1.dll`, `dwrite.dll`, `ntdll.dll`, and the delay-load helper
  builtins all built by the same mingw-w64-gcc 16.1.0 — consistent ABI.
- LR's dwrite delay-load should resolve cleanly.
- Next crash (if any) becomes visible.

## Risk

- 1-3 hours of build time on 16-core ThinkPad.
- Whole-tree rebuild may introduce other regressions if upstream
  PhialsBasement patches assumed older mingw behavior.
- WoW64 single-tree differs from bundled 32+64 separate-binary layout
  — Proton wrapper paths in `~/opt/wine-adobe/` won't match. Launching
  by absolute path to new `wine64` binary should still work.
