#!/usr/bin/env python3
"""
Patch lightroom.exe to null-check a COM interface pointer before dereferencing.

The crash
---------
LR worker thread crashes:

    EXCEPTION_ACCESS_VIOLATION_READ  addr=0x0
     0  lightroom.exe + 0x28231c   rcx=0, rdi=0x80010106 (RPC_E_WRONG_THREAD)

Disassembly at the crash site (image base 0x140000000):

    140282312:  call  [rip+0x9e2b80]      ; helper, leaves [rbp-0x30] possibly NULL
    140282318:  mov   rcx,[rbp-0x30]      ; rcx = COM interface ptr
    14028231c:  mov   rax,[rcx]           ; <-- CRASH: rcx is NULL
    14028231f:  lea   r9,[rbp+0x28]
    140282323:  lea   r8,[rbp-0x20]
    140282327:  mov   edx,1
    14028232c:  call  [rax+0x18]

When an upstream COM method returns RPC_E_WRONG_THREAD (Wine's COM
apartment-threading differs from Windows), [rbp-0x28] is left NULL, the
QueryInterface at 0x1402822f9 is skipped, and [rbp-0x30] is never written.
The code then dereferences it unconditionally and faults.

The fix
-------
Redirect 0x14028231c into a code cave that test-checks rcx. If NULL, jump
to LR's own error path at 0x1402823a5 (which releases [rbp-0x20] and
returns a failure byte -- a clean, already-present unwind). If non-NULL,
run the original `mov rax,[rcx]` + `lea r9,[rbp+0x28]` and continue.

This is a targeted, idempotent binary patch. Re-running detects the patch
and does nothing. Restore from backups/lightroom.exe.orig to revert.
"""
import os
import struct
import sys
import shutil

LR = os.path.expanduser(
    "~/.wine_adobe/drive_c/Program Files/Adobe/Adobe Lightroom CC/lightroom.exe"
)
BACKUP = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "backups", "lightroom.exe.orig",
)

IMAGE_BASE = 0x140000000
TEXT_VMA = 0x140001000
TEXT_FOFF = 0x400


def v2f(vma):
    """.text VMA -> file offset."""
    return vma - TEXT_VMA + TEXT_FOFF


# --- addresses (VMA) ---
CRASH = 0x14028231C          # patch site: original `mov rax,[rcx]`
CONT = 0x140282323           # `lea r8,[rbp-0x20]` -- resume point
ERRPATH = 0x1402823A5        # LR's own error/unwind path
CAVE = 0x140A027BA           # 22-byte 0xCC code cave in .text

ORIG_AT_CRASH = bytes.fromhex("48 8b 01 4c 8d 4d 28".replace(" ", ""))
# mov rax,[rcx] ; lea r9,[rbp+0x28]


def rel32(src_end, target):
    """rel32 displacement for an instruction whose *next* byte is src_end."""
    d = target - src_end
    return struct.pack("<i", d)


def build_cave():
    """21 bytes: test/jz-error/mov/lea/jmp-back."""
    b = bytearray()
    b += bytes.fromhex("4885C9")                       # test rcx,rcx
    # jz ERRPATH  -- 0f 84 rel32
    b += b"\x0f\x84"
    b += rel32(CAVE + len(b) + 4, ERRPATH)
    b += bytes.fromhex("488B01")                       # mov rax,[rcx]
    b += bytes.fromhex("4C8D4D28")                     # lea r9,[rbp+0x28]
    # jmp CONT  -- e9 rel32
    b += b"\xe9"
    b += rel32(CAVE + len(b) + 4, CONT)
    return bytes(b)


def main():
    if not os.path.exists(LR):
        sys.exit("lightroom.exe not found: %s" % LR)

    data = bytearray(open(LR, "rb").read())
    cf = v2f(CRASH)
    cavef = v2f(CAVE)

    # idempotency: already patched?
    if data[cf] == 0xE9:
        print("already patched (jmp at 0x%x) -- nothing to do" % CRASH)
        return

    if bytes(data[cf:cf + 7]) != ORIG_AT_CRASH:
        sys.exit("unexpected bytes at crash site: %s"
                 % data[cf:cf + 7].hex(" "))

    if any(x != 0xCC for x in data[cavef:cavef + 22]):
        sys.exit("code cave at 0x%x is not free (expected 22x 0xCC)" % CAVE)

    # backup
    if not os.path.exists(BACKUP):
        shutil.copy2(LR, BACKUP)
        print("backup -> %s" % BACKUP)

    # 1) write the cave
    cave = build_cave()
    assert len(cave) <= 22, len(cave)
    data[cavef:cavef + len(cave)] = cave

    # 2) redirect crash site: e9 rel32 -> CAVE  (5 bytes)
    jmp = b"\xe9" + rel32(CRASH + 5, CAVE)
    data[cf:cf + 5] = jmp
    # bytes at CRASH+5..CRASH+6 (`4d 28`) are now dead -- harmless.

    open(LR, "wb").write(data)
    print("patched lightroom.exe")
    print("  crash site 0x%x: %s" % (CRASH, jmp.hex(" ")))
    print("  cave       0x%x: %s" % (CAVE, cave.hex(" ")))


if __name__ == "__main__":
    main()
