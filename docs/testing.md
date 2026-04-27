# Testing

## Fast Checks

Run shellcheck over all scripts:

```sh
shellcheck scripts/*.sh scripts/lib/*.sh scripts/approaches/*.sh tests/*.sh tests/container/*.sh
```

Run the dry-run smoke test:

```sh
tests/smoke.sh --dry-run
```

Run the Arch container smoke test:

```sh
tests/container/run.sh
```

The container check uses `archlinux:latest`, installs `base-devel` and `git`, mounts the repository read-only, and runs `scripts/install.sh --non-interactive --dry-run` through `tests/smoke.sh`.

## GUI Install Validation

The real Lightroom validation must run in a GUI-capable Arch environment, not in CI. Use one of these paths:

- QEMU/KVM Arch VM with GPU passthrough for the most realistic Develop-module test.
- QEMU/KVM Arch VM with virtio graphics for installer and launch checks.
- Xvfb only for installer smoke, not for the Develop performance criterion.

Record the environment in `docs/results-<approach>.md`:

- Host distro and kernel.
- CPU, memory, GPU vendor, and driver stack.
- Wine runner and version.
- Lightroom version and installer source.
- Exact commands.
- Log excerpts.
- Screenshots under `docs/screenshots/<approach>/`.

Working criteria:

1. Lightroom launches and stays open for at least 2 minutes idle.
2. Lightroom imports the RAW file supplied by `$LR_TEST_RAW`, or a CC0 fixture downloaded into `tests/fixtures/`.
3. Exposure and contrast edits in Develop give feedback in under 2 seconds.
4. JPEG export succeeds and is verified with `file` and ImageMagick `identify`.

Do not commit proprietary installers, catalogs, RAW files larger than the fixture policy allows, or Adobe binaries.
