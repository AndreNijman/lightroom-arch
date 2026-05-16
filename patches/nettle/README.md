# patches/nettle — fix for 32-bit `lib32-nettle` ECC TLS abort

The attempt-17 networking wall was, finally, **a broken `lib32-nettle`
package on this Arch host** — not Wine, not Adobe. This directory holds
the fix.

## The bug

Any 32-bit (`i386`) process doing an elliptic-curve TLS handshake
through `lib32-gnutls` → `lib32-nettle` aborts:

```
ecc-random.c:62: _nettle_ecc_mod_random: Assertion `nbytes <= m->size * sizeof (mp_limb_t)' failed.
```

64-bit is fine — same `nettle 4.0` / `gnutls 3.8.13` upstream versions.
The Adobe CC installer (`Set-up.exe`, a `PE32 i386` binary) hits this on
every HTTPS request → its sign-in workflow parks.

## Root cause

The Arch `lib32-nettle` PKGBUILD configures nettle with
`--with-include-path=/usr/lib32/gmp`. **nettle 4.0 deleted that option**
(nettle `NEWS`: *"The unusual configure options `--with-lib-path` and
`--with-include-path` has been deleted. Use CFLAGS and LDFLAGS"*).
`configure` silently ignores the unknown flag.

So the 32-bit build never sees the 32-bit `gmp.h`
(`GMP_LIMB_BITS == 32`) that `lib32-gmp` ships at `/usr/lib32/gmp/gmp.h`.
`configure`'s `AC_COMPUTE_INT(GMP_NUMB_BITS, [#include <gmp.h>])` reads
the **64-bit** `/usr/include/gmp.h` and sets `NUMB_BITS=64`. nettle's
`eccdata` tool then generates every ECC constant table for 64-bit limbs.
In the 32-bit library `struct ecc_modulo.size` ends up half the real
limb count — P-256: **4** instead of **8** — so at `ecc-random.c:62`,
`nbytes=32 > m->size*sizeof(mp_limb_t)=4*4=16` → the assertion aborts.

## The fix

`lib32-nettle-cppflags-gmp32.patch` — pass the 32-bit gmp include dir
via `CPPFLAGS` (`-I/usr/lib32/gmp`), exactly as nettle 4.0 documents.
`PKGBUILD` here is the full corrected file.

`configure` then detects `GMP limb size... 32 bits`, `eccdata`
generates correct 32-bit tables, `ecc_modulo.size = 8` for P-256, and
the assertion is **legitimately satisfied** (`32 <= 8*4`). No nettle
source is touched; **no assertion or bounds check is weakened**. The
fix only makes the 32-bit build a normal 32-bit nettle build — the same
configuration nettle ships and tests on every genuine 32-bit platform
(i686, ARM32, …).

## Verification

- `repro/nettle-i386/` — Wine-free native reproducer. Stock
  `lib32-nettle 4.0-1` → abort; rebuilt → `HANDSHAKE OK`.
- nettle's own 32-bit testsuite on the rebuilt library: **All 116 tests
  passed** (every `ecc-*`, `ecdsa-*`, `eddsa-*`, `curve*` test) — proof
  the ECC math is correct, not merely un-aborted.
- `wine-patches/repro-winhttp-adobe/httptest32.exe cc-api-data.adobe.io`
  → `HTTP 403` (was `err=12157`). The installer's networking wall is
  gone on the 32-bit path.

## Build & install

```sh
mkdir build && cd build && cp /path/to/patches/nettle/PKGBUILD .
makepkg -f --skippgpcheck          # downloads nettle-4.0 tarball, builds
sudo pacman -U lib32-nettle-4.0-1-x86_64.pkg.tar.zst
```

Revert to the stock (broken) package: `sudo pacman -S lib32-nettle`.
A future official Arch update will overwrite this rebuild — ideally
with the same fix once reported.

## Report destination

This is an **Arch packaging bug** — report at `bugs.archlinux.org` /
the `lib32-nettle` package on `gitlab.archlinux.org`. It is **not** a
nettle upstream bug: nettle removed the option deliberately and
documented the `CFLAGS`/`LDFLAGS` replacement in `NEWS`.
