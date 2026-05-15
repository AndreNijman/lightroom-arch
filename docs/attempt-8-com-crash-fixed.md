# Attempt 8: The COM Wrong-Thread Crash — Fixed

## Where attempt 7 left off

LR launched, signed in, loaded its complete main UI — then a worker
thread crashed and LR popped its "Sorry, an error occurred" crash
reporter. The crash:

```
EXCEPTION_ACCESS_VIOLATION_READ  addr=0x0
 0  lightroom.exe + 0x28231c   rcx=0, rdi=0x80010106 (RPC_E_WRONG_THREAD)
 1  mfc140u.dll + 0x2835
 2  lightroom.exe + 0x20ff56
```

## Diagnosis — disassembling the crash site

`lightroom.exe` image base is `0x140000000`. Disassembly around the
crash (`objdump -d -M intel`):

```
140282312:  call  [rip+0x9e2b80]      ; helper -> may leave [rbp-0x30] NULL
140282318:  mov   rcx,[rbp-0x30]      ; rcx = a COM interface pointer
14028231c:  mov   rax,[rcx]           ; <-- CRASH: rcx is NULL
14028231f:  lea   r9,[rbp+0x28]
140282323:  lea   r8,[rbp-0x20]
140282327:  mov   edx,1
14028232c:  call  [rax+0x18]          ; virtual call (vtable+0x18)
```

Walking back: at `0x1402822e6` the code does `test rcx,rcx ; je
0x140282305`. `rcx` there is `[rbp-0x28]`, an interface that an
upstream call (`0x1402822df`) was supposed to fill. When that upstream
COM method returns `RPC_E_WRONG_THREAD`, `[rbp-0x28]` is left NULL, so
the `QueryInterface` at `0x1402822f9` (which would have written
`[rbp-0x30]`) is **skipped**. Execution still falls through to
`0x140282318`, which reads the never-initialised `[rbp-0x30]` and
dereferences it.

`RPC_E_WRONG_THREAD` (0x80010106) means a COM interface was used from a
thread other than the apartment it was marshalled for. Wine's COM
apartment-threading model differs from Windows, so LR's media/AgKernel
worker hits a path that Windows never exercises — and LR's own code has
no NULL guard on it.

## The fix — a code-cave null check in lightroom.exe

Rather than chase Wine's COM apartment model (months of Wine work), the
crash was fixed where it actually faults: a targeted binary patch to
`lightroom.exe`.

`0x14028231c` is redirected (`jmp`) into a 22-byte run of `int3`
padding (a code cave) elsewhere in `.text`. The cave:

```
test rcx,rcx
jz   0x1402823a5      ; LR's own error/unwind path
mov  rax,[rcx]        ; original instruction
lea  r9,[rbp+0x28]    ; original next instruction
jmp  0x140282323      ; resume
```

`0x1402823a5` is LR's *existing* error path for this function — it
releases the local at `[rbp-0x20]` and returns a failure byte. So on
the NULL case the worker now unwinds cleanly instead of faulting; on
the normal case behaviour is byte-identical to the original.

Applied by `scripts/patches/patch-lightroom-com-nullcheck.py`
(idempotent; computes all `rel32` offsets; verifies original bytes
before writing). `backups/lightroom.exe.orig` is the untouched binary.

## Result

With the patch, LR launches and:

- Signs in, authenticates against Adobe Creative Cloud
- Loads its complete main UI — Local library workspace
- **Stays alive** — no worker-thread crash, no "Sorry, an error
  occurred" dialog, no crash dump generated

Verified: a clean run stayed up well past the point where every
unpatched run crashed (the unpatched runs dumped within ~1-2 min; the
patched run ran crash-free with zero dumps in the crash directory).

## Note on LR's single-instance behaviour

LR is single-instance. If an LR process is already running in the
prefix, a second `lightroom.exe` detects it via a lock, signals the
running instance, and exits 0 — so the *patched* binary only takes
effect once every prior LR process in the prefix is killed
(`wineserver -k9`) before launching.
