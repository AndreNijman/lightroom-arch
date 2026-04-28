#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

: "${LIGHTROOM_ARCH_APP_ID:=lightroom-arch}"
: "${LIGHTROOM_ARCH_LOG_DIR:=${XDG_STATE_HOME:-${HOME}/.local/state}/${LIGHTROOM_ARCH_APP_ID}}"
if [[ -z "${LIGHTROOM_ARCH_LOG_PATH:-}" ]]; then
  LIGHTROOM_ARCH_LOG_TIMESTAMP=$(date +%s)
  LIGHTROOM_ARCH_LOG_PATH="${LIGHTROOM_ARCH_LOG_DIR}/install-${LIGHTROOM_ARCH_LOG_TIMESTAMP}.log"
fi

log::init() {
  mkdir -p "${LIGHTROOM_ARCH_LOG_DIR}"
  : > "${LIGHTROOM_ARCH_LOG_PATH}"
}

log::path() {
  printf '%s\n' "${LIGHTROOM_ARCH_LOG_PATH}"
}

log::line() {
  local level=$1
  shift
  local message=$*
  printf '[%s] %s\n' "${level}" "${message}" | tee -a "${LIGHTROOM_ARCH_LOG_PATH}"
}

log::info() {
  log::line INFO "$@"
}

log::warn() {
  log::line WARN "$@"
}

log::error() {
  log::line ERROR "$@"
}

log::die() {
  log::error "$@"
  return 1
}
