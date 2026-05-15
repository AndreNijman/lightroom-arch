# Attempt 5: Resume Notes — Build Paused

Build paused mid-compile per user. State preserved for resume.

## Where build stopped

- Source: `/tmp/wine-src` on `proton_10.0` branch
- Build dir: `/tmp/wine-src/build` (~628MB of compiled objects)
- Wine loader binary present at `/tmp/wine-src/build/wine`
- d2d1 ColorManagement patch live in `dlls/d2d1/effect.c`
- Generated request handlers refreshed via `tools/make_requests`

## To resume

```bash
cd /tmp/wine-src/build
make -j16 > ~/Projects/lightroom-arch/logs/wine-build.log 2>&1
```

Incremental — picks up from current object state. 30-90 min remaining
on 16-core ThinkPad (rough estimate based on what's done vs not).

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
