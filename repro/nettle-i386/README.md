# repro/nettle-i386 — 32-bit nettle TLS bug, Wine-free reproducer

Minimal **native Linux** reproducer for the attempt-17 networking wall.
No Wine, no Adobe software — proves the bug is in the host's 32-bit
crypto stack, not in Wine.

## The bug

The Arch `lib32-nettle 4.0` package is mis-built: a stale
`--with-include-path` configure flag (deleted in nettle 4.0) makes the
32-bit build generate ECC tables for 64-bit limbs. A 32-bit process
doing any NIST-curve TLS handshake through GnuTLS then aborts:

```
ecc-random.c:62: _nettle_ecc_mod_random: Assertion `nbytes <= m->size * sizeof (mp_limb_t)' failed.
```

(On an X25519 + ChaCha20-Poly1305 handshake the failure mode is instead a
wrong outbound AEAD tag → server `bad_record_mac` alert. Same root cause.)

64-bit is fine — same `nettle`/`gnutls` upstream versions. The only
variable is ILP32 vs LP64. Full root cause + fix: `patches/nettle/`.

## Build & run

```sh
make                       # builds ntls-handshake64 and ntls-handshake32
./ntls-handshake64 www.microsoft.com           # HANDSHAKE OK
LD_LIBRARY_PATH=/usr/lib32 ./ntls-handshake32 www.microsoft.com
#   stock lib32-nettle 4.0-1 -> aborts in nettle
#   rebuilt with patches/nettle/ -> HANDSHAKE OK
```

`ntls-handshake32` needs `gcc` multilib + `lib32-gnutls` (Arch multilib
repo). Binaries are gitignored.

## Why this matters

The attempt-17 installer wall (`Set-up.exe`, a `PE32 i386` binary, fails
every HTTPS request inside Wine) was first misdiagnosed as a 32-bit Wine
`secur32` bug. This native reproducer removes Wine entirely and the crash
is identical — so the defect is the host's `lib32-nettle` package,
nothing Wine or Adobe ships. Fixed in `patches/nettle/`; see
`docs/attempt-17-cc-desktop.md`.

Report destination: the Arch `lib32-nettle` package (`bugs.archlinux.org`
/ `gitlab.archlinux.org`) — **not** nettle upstream (nettle removed the
option deliberately and documented the `CFLAGS`/`LDFLAGS` replacement).
