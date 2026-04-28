# Failure documentation: Adobe Lightroom on Arch via Wine

## What this is

This repo is failure documentation for installing Adobe Lightroom on Arch Linux via Wine in 2026. It is not a working installer. It exists so the next person attempting this can see what was tried, what blocked it, and skip the dead-ends.

## Status

Not working. Final. Four approaches were tested on 2026-04-28. All were blocked upstream.

## Approaches tested

| Approach | Runtime | Blocker | Evidence file |
| --- | --- | --- | --- |
| Lutris, Lightroom 6.14 target | Lutris-style Wine prefix | Adobe ended Lightroom 6.14 distribution; the available input was a Creative Cloud bootstrapper, not an LR 6.14 installer. | [docs/results-lutris.md](docs/results-lutris.md) |
| Wine vanilla + winetricks, Lightroom cloud | System Wine + winetricks | Adobe bootstrapper requires IE/MSHTML/JScript; current winetricks removed the `mshtml` verb. | [docs/results-wine-cc-cloud.md](docs/results-wine-cc-cloud.md) |
| Bottles caffe + browser deps, Lightroom cloud | Bottles Flatpak, `caffe-9.7` | Native browser DLL path aborts at `wininet.dll.InternetOpenA` because `iertutil.dll` is not satisfiable. | [docs/results-bottles-cc-cloud.md](docs/results-bottles-cc-cloud.md) |
| Bottles soda + default deps, Lightroom cloud | Bottles Flatpak, `soda-9.0-1` | Creative Cloud Installer opens as a black Xwayland window; Wine logs missing COM registration and RPC binding failures. | [docs/results-bottles-cc-cloud.md](docs/results-bottles-cc-cloud.md) |

## Upstream blockers (none of which this repo can fix)

- Adobe ended Lightroom 6.14 download distribution on 2023-12-31. See [docs/upstream-blockers.md](docs/upstream-blockers.md).
- `winetricks 20260125` removed the `mshtml` verb because the old IE8 redistributable path is gone. See [docs/upstream-blockers.md](docs/upstream-blockers.md).
- The IE, `iertutil`, and COM stack required by Adobe's current bootstrapper is non-functional on modern Wine. See [docs/why-this-doesnt-work.md](docs/why-this-doesnt-work.md).

## What works instead in 2026

- darktable: install with `pacman -S darktable`; handles Nikon NEFs and provides non-destructive RAW editing.
- RawTherapee: RAW processor with strong demosaicing, color, and export controls.
- digiKam: photo manager with RAW import, tagging, metadata, and editing tools.

## Reproducing the failures

The scripts under `scripts/approaches/` remain in the repo as reproducible failure harnesses. Preflight, container smoke, and shellcheck are expected to pass. Nothing here will install Lightroom; running the scripts produces the same documented failures.

```sh
shellcheck scripts/*.sh scripts/lib/*.sh scripts/approaches/*.sh tests/*.sh tests/container/*.sh
tests/smoke.sh --dry-run
tests/container/run.sh
```

## Repo structure

```text
docs/
  research-*.md
  results-*.md
  screenshots/
  upstream-blockers.md
  why-this-doesnt-work.md
scripts/
  approaches/
  lib/
tests/
  container/
```

## Contributing

Closed. This repo is not accepting PRs that attempt new Wine approaches without addressing the IE/COM structural issue documented in [docs/why-this-doesnt-work.md](docs/why-this-doesnt-work.md). Anyone with a working modern Lightroom on Wine recipe should open an issue with reproducible evidence first.

## License

MIT. See [LICENSE](LICENSE).
