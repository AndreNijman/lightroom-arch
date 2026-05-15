# Attempt 5: Resume Notes

## Reboot wiped /tmp

First build attempt used `/tmp/wine-src` — `/tmp` is tmpfs, wiped on
reboot. 628MB of compiled objects lost. Source re-cloned to a
persistent location.

## Current build location

- Source: `~/wine-build/wine-src` on `proton_10.0` branch (shallow clone)
- Build dir: `~/wine-build/wine-src/build`
- d2d1 ColorManagement patch applied to `dlls/d2d1/effect.c`
- `tools/make_requests` run to regenerate fsync/esync request handlers
- `./autogen.sh` run (shallow clone has no `configure` script)
- Configured: `--prefix=$HOME/opt/wine-adobe-built
  --enable-archs=i386,x86_64 --disable-tests`

## To resume build

```bash
cd ~/wine-build/wine-src/build
make -j16 > ~/Projects/lightroom-arch/logs/wine-build.log 2>&1
```

Incremental — picks up from current object state. Full clean build
is 1-3h on 16-core ThinkPad.

## After build finishes

Run `~/Projects/lightroom-arch/scripts/approaches/install-rebuilt-wine-test-lr.sh`:
1. Kill stale wine procs + close zombie windows
2. `make install` to `~/opt/wine-adobe-built`
3. Launch LR via new `wine` binary against existing `~/.wine_adobe` prefix

## Why pause

Long build (1-3h total). User paused to free machine.

## Fallback if rebuild still crashes dwrite

Native DWrite.dll confirmed at `/mnt/windows/Windows/System32/DWrite.dll`
(2.4MB). Copy in:

```bash
cp /mnt/windows/Windows/System32/DWrite.dll \
  ~/.wine_adobe/drive_c/windows/system32/dwrite.dll
# Launch with WINEDLLOVERRIDES="...;dwrite=n"
```
