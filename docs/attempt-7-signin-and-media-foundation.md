# Attempt 7: Past Sign-In — SetThreadpoolTimerEx and the Media Foundation Wall

## Where attempt 6 left off

LR launched, rendered its UI, and showed the Adobe sign-in page. After
the user actually signed in, a new failure appeared:

```
wine: Call from ... to unimplemented function
      KERNEL32.dll.SetThreadpoolTimerEx, aborting
```

## SetThreadpoolTimerEx

The bundled PhialsBasement Wine 10.0 does not export
`SetThreadpoolTimerEx` from `kernel32`. `AdobeGrowthSDK.dll` (Adobe's
post-sign-in analytics/growth component) imports it. Wine binds the
missing import to an abort-stub; calling it kills the process.

### What did not work

Rebuilding `kernel32.dll` + `kernelbase.dll` from source with the
function added: the rebuilt core DLLs are ABI-incompatible with the
bundled Wine's `ucrtbase`/`vcruntime140` (the bundled binary was built
from a different commit/toolchain). Installing them cascaded init
failures — `ucrtbase.dll failed to initialize`, then
`VCRUNTIME140.dll failed to initialize`. Core Wine DLLs cannot be
swapped piecemeal; reverted to the bundled originals.

A WoW64-vs-classic build-mode difference was ruled out (the x86_64 PE
DLLs are byte-identical between `--enable-archs` and `--enable-win64`).

### What worked — binary patch on AdobeGrowthSDK.dll

`AdobeGrowthSDK.dll` was the only module importing
`SetThreadpoolTimerEx`. Binary-patched its import name table: the
import string `SetThreadpoolTimerEx` → `SetThreadpoolTimer\0\0` (the
final `Ex` overwritten with NUL bytes). The import now resolves to the
real `SetThreadpoolTimer` (which `kernel32` does export, forwarded to
`ntdll.TpSetTimer`). Same four arguments; the only loss is the BOOL
return value (`SetThreadpoolTimer` returns void), which the Growth SDK
telemetry path tolerates.

Patch offset in `AdobeGrowthSDK.dll`: byte 5951432, `45 78` ("Ex") →
`00 00`. Revert by writing `45 78` back.

## Result — sign-in works

With the patch, LR:
- Gets past the `SetThreadpoolTimerEx` abort
- Completes Adobe Creative Cloud sign-in / activation
- Renders the post-login **"What's New — April 2026"** screen
  (WebView2 content)

## Remaining blocker: Media Foundation

LR then crashes:

```
EXCEPTION_ACCESS_VIOLATION_READ  addr=0x0
 0  MF.dll + 0x18e0f      rax=0x80004002 (E_NOINTERFACE)
 1  ucrtbase.dll + 0x46af0
   thread 57 (media worker)
```

Wine's builtin Media Foundation (`mf.dll`) queries a COM interface,
gets `E_NOINTERFACE`, and dereferences the null result. This is a Wine
MF incompleteness, hit during LR's media/video subsystem startup.

Disabling MF (`WINEDLLOVERRIDES "mf=d;mfplat=d;mfreadwrite=d"`) does
not help — LR hard-requires `mf.dll` to load and raises
`0xC06D007E` ("module not found") if it is absent.

### MF DLL swap got past it

Rebuilt `mf.dll`, `mfplat.dll`, `mfreadwrite.dll` from the Wine source
tree and swapped them into the bundled Wine (the same leaf-DLL swap
that worked for `d2d1`). The Media Foundation crash no longer fires —
LR proceeds past media init.

## How far LR gets now

With every fix applied (d2d1 patch, builtin dwrite, WineD3D, WebView2,
AdobeGrowthSDK patch, rebuilt MF DLLs), LR:

- Launches, signs in, authenticates against Adobe Creative Cloud
- Renders the post-login "What's New" screen
- **Loads its complete main UI** — the Local library workspace with
  the Cloud/Local panel, Assisted Culling, Favorites/Browse, and the
  "Work directly / Selectively copy / Bookmark / Auto-save" onboarding

## Final blocker: COM wrong-thread crash

A worker thread then crashes:

```
EXCEPTION_ACCESS_VIOLATION_READ  addr=0x0
 0  lightroom.exe + 0x28231c   (all registers zero — null deref)
   rdi = 0x80010106  (RPC_E_WRONG_THREAD)
   thread 53
```

`lightroom.exe+0x28231C` makes a COM call, gets `RPC_E_WRONG_THREAD`
(the interface was marshalled for a different apartment), and
dereferences the null result. This is LR's own code, exposed by
Wine's COM apartment-threading model differing from Windows. The same
address crashed in several earlier runs.

Fixing it needs either binary-patching `lightroom.exe` (locating
+0x28231C in a 26 MB stripped binary and adding a null check) or
correcting Wine's COM apartment behaviour — both deep.

## Status

LR launches, signs in, authenticates, and loads its full main UI.
It is not yet a stable daily-usable LR: a Wine COM-threading bug
crashes a worker thread shortly after the UI finishes loading.
