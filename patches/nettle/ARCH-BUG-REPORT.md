# Arch bug report — paste-ready

Submit as a new issue at:
**https://gitlab.archlinux.org/archlinux/packaging/packages/lib32-nettle/-/issues**

(Requires a gitlab.archlinux.org account. Everything below the line is
the report body — title separate.)

---

## Title

`lib32-nettle 4.0-1: 32-bit ECC TLS broken — stale --with-include-path flag, aborts in _nettle_ecc_mod_random`

## Body

### Summary

`lib32-nettle 4.0-1` is mis-built. Every 32-bit (`i386`) process that
performs a NIST-curve elliptic-curve TLS handshake through `lib32-gnutls`
aborts:

```
ecc-random.c:62: _nettle_ecc_mod_random: Assertion `nbytes <= m->size * sizeof (mp_limb_t)' failed.
```

This breaks all 32-bit ECDSA/ECDH TLS — e.g. any 32-bit app under Wine,
or any native `-m32` GnuTLS client. 64-bit `nettle` is unaffected.

### Affected package

`lib32-nettle 4.0-1` (multilib). `nettle 4.0-1` (64-bit) is fine.

### Root cause

The `lib32-nettle` `PKGBUILD` `build()` runs:

```sh
./configure --prefix=/usr --libdir=/usr/lib32 \
  --enable-shared --with-include-path=/usr/lib32/gmp
```

**nettle 4.0 deleted the `--with-include-path` option.** From nettle's
`NEWS`:

> The unusual configure options `--with-lib-path` and
> `--with-include-path` has been deleted. Use CFLAGS and LDFLAGS [...]

`configure` now silently ignores it:

```
configure: WARNING: unrecognized options: --with-include-path
```

So the 32-bit build no longer sees the 32-bit `gmp.h`
(`GMP_LIMB_BITS == 32`) that `lib32-gmp` ships at `/usr/lib32/gmp/gmp.h`.
nettle's `configure` runs `AC_COMPUTE_INT(GMP_NUMB_BITS, [#include
<gmp.h>])`, picks up the **64-bit** `/usr/include/gmp.h`, and sets
`NUMB_BITS=64`:

```
checking for GMP limb size... 64 bits     # should be 32
```

nettle's `eccdata` build tool then generates every ECC constant table
for 64-bit limbs. In the 32-bit library `struct ecc_modulo.size` ends up
half the real limb count (P-256: 4 instead of 8). At `ecc-random.c:62`,
`nbytes = 32` but `m->size * sizeof(mp_limb_t) = 4 * 4 = 16`, so the
assertion fails and the process aborts.

### Steps to reproduce

```sh
cat > t.c <<'EOF'
#include <gnutls/gnutls.h>
#include <string.h>
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
#include <stdio.h>
int main(void){
  const char*h="www.microsoft.com";
  gnutls_global_init();
  gnutls_session_t s; gnutls_certificate_credentials_t c;
  gnutls_certificate_allocate_credentials(&c);
  gnutls_init(&s,GNUTLS_CLIENT);
  gnutls_set_default_priority(s);
  gnutls_credentials_set(s,GNUTLS_CRD_CERTIFICATE,c);
  gnutls_server_name_set(s,GNUTLS_NAME_DNS,h,strlen(h));
  struct addrinfo hi={0},*r; hi.ai_socktype=SOCK_STREAM;
  getaddrinfo(h,"443",&hi,&r);
  int fd=socket(r->ai_family,SOCK_STREAM,0);
  connect(fd,r->ai_addr,r->ai_addrlen);
  gnutls_transport_set_int(s,fd);
  gnutls_handshake_set_timeout(s,10000);
  int x; do{x=gnutls_handshake(s);}while(x<0&&!gnutls_error_is_fatal(x));
  printf(x<0?"FAIL\n":"OK\n"); return 0;
}
EOF
gcc -m32 t.c -o t32 -L/usr/lib32 -lgnutls
LD_LIBRARY_PATH=/usr/lib32 ./t32
# -> ecc-random.c:62: _nettle_ecc_mod_random: Assertion ... failed.
```

The 64-bit build (`gcc t.c -o t64 -lgnutls; ./t64`) prints `OK`.

### Fix

Pass the 32-bit gmp include directory via `CPPFLAGS`, as nettle 4.0
documents. In `build()`:

```diff
   export CC="gcc -m32"
   export CXX="g++ -m32"
   export PKG_CONFIG_PATH="/usr/lib32/pkgconfig"
+  export CPPFLAGS="-I/usr/lib32/gmp${CPPFLAGS:+ $CPPFLAGS}"

   ./configure --prefix=/usr --libdir=/usr/lib32 \
-    --enable-shared --with-include-path=/usr/lib32/gmp
+    --enable-shared
```

`configure` then reports `checking for GMP limb size... 32 bits`,
`eccdata` generates correct 32-bit tables, and the rebuilt library
passes nettle's full 32-bit testsuite (`All 116 tests passed`).

### Notes

- This is a packaging bug, not a nettle upstream bug — nettle removed
  the option deliberately and documented the replacement.
- Likely also worth a `check()` that runs `make -k check`; it would have
  caught this (the ECC tests abort).
