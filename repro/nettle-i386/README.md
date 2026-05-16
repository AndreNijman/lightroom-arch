# repro/nettle-i386 — 32-bit nettle TLS bug, Wine-free reproducer

Minimal **native Linux** reproducer for the attempt-17 networking wall.
No Wine, no Adobe software — proves the bug is in the host's 32-bit
crypto stack, not in Wine.

## The bug

`nettle 4.0` / `lib32-nettle 4.0` (`libnettle.so.9`) is broken on `i386`.
A 32-bit process doing any TLS handshake through GnuTLS aborts:

```
ecc-random.c:62: _nettle_ecc_mod_random: Assertion `nbytes <= m->size * sizeof (mp_limb_t)' failed.
```

(On an X25519 + ChaCha20-Poly1305 handshake the failure mode is instead a
wrong outbound AEAD tag → server `bad_record_mac` alert. Same root cause.)

64-bit is fine — same `nettle`/`gnutls` upstream versions. The only
variable is ILP32 vs LP64.

## Build & run

```sh
make                       # builds ntls-handshake64 and ntls-handshake32
./ntls-handshake64 www.microsoft.com           # HANDSHAKE OK
LD_LIBRARY_PATH=/usr/lib32 ./ntls-handshake32 www.microsoft.com   # aborts in nettle
```

`ntls-handshake32` needs `gcc` multilib + `lib32-gnutls` (Arch multilib
repo). Binaries are gitignored.

## Why this matters

The attempt-17 installer wall (`Set-up.exe`, a `PE32 i386` binary, fails
every HTTPS request inside Wine) was first misdiagnosed as a 32-bit Wine
`secur32` bug. This native reproducer removes Wine entirely and the crash
is identical — so the defect is upstream `nettle`/`lib32-nettle`, nothing
Wine or Adobe ships. See `docs/attempt-17-cc-desktop.md`.

Report destination: upstream `nettle` (`nettle-bugs` list /
`gitlab.com/gnutls/nettle`) and/or an Arch `lib32-nettle` packaging bug.
