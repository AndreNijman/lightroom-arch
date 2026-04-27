#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)

smoke::assert_contains() {
  local needle=$1
  local file=$2
  if ! grep -Fq "${needle}" "${file}"; then
    printf 'Expected smoke output to contain: %s\n' "${needle}" >&2
    printf '--- output ---\n' >&2
    sed -n '1,220p' "${file}" >&2
    return 1
  fi
}

smoke::dry_run() {
  local tmp_home
  tmp_home=$(mktemp -d)
  local output="${PROJECT_ROOT}/test-output/smoke-dry-run.log"
  mkdir -p "${PROJECT_ROOT}/test-output"
  HOME="${tmp_home}" \
    XDG_DATA_HOME="${tmp_home}/.local/share" \
    XDG_STATE_HOME="${tmp_home}/.local/state" \
    "${PROJECT_ROOT}/scripts/install.sh" \
      --non-interactive \
      --dry-run \
      --approach lutris \
      --version 5.7.1 \
      --installer "${PROJECT_ROOT}/tests/fixtures/Lightroom_5.7.1.exe" \
      > "${output}" 2>&1
  smoke::assert_contains "install.phase=preflight" "${output}"
  smoke::assert_contains "approach=lutris version=5.7.1" "${output}"
  smoke::assert_contains "smoke.dry_run=passed" "${output}"
  smoke::assert_contains "desktop.entry=" "${output}"
  rm -rf "${tmp_home}"
}

smoke::installed() {
  printf 'Installed GUI smoke test is documented in docs/testing.md and is not automated here.\n'
}

case "${1:-}" in
  --installed)
    smoke::installed
    ;;
  ''|--dry-run)
    smoke::dry_run
    ;;
  *)
    printf 'Usage: tests/smoke.sh [--dry-run|--installed]\n' >&2
    exit 2
    ;;
esac
