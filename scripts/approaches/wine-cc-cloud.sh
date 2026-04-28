#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../.." && pwd)

for lib in "${PROJECT_ROOT}"/scripts/lib/*.sh; do
  # shellcheck source=/dev/null
  source "${lib}"
done

: "${LIGHTROOM_CC_PREFIX:=${HOME}/.wine-lightroom-cc}"
: "${LIGHTROOM_CC_EXE:=${LIGHTROOM_CC_PREFIX}/drive_c/Program Files/Adobe/Adobe Lightroom/Lightroom.exe}"

LIGHTROOM_ARCH_INSTALLER=''
LIGHTROOM_ARCH_VERSION='cc-cloud'

cc_cloud::usage() {
  cat <<'USAGE'
Usage: scripts/approaches/wine-cc-cloud.sh --installer PATH [--version cc-cloud] [--non-interactive] [--dry-run]
USAGE
}

cc_cloud::parse_args() {
  while (($#)); do
    case "$1" in
      --installer)
        shift
        LIGHTROOM_ARCH_INSTALLER=${1:-}
        ;;
      --version)
        shift
        LIGHTROOM_ARCH_VERSION=${1:-}
        ;;
      --dry-run)
        export LIGHTROOM_ARCH_DRY_RUN=1
        ;;
      --non-interactive)
        export LIGHTROOM_ARCH_NON_INTERACTIVE=1
        ;;
      -h|--help)
        cc_cloud::usage
        exit 0
        ;;
      *)
        log::die "Unknown wine-cc-cloud argument: $1"
        ;;
    esac
    shift
  done
  [[ -n "${LIGHTROOM_ARCH_INSTALLER}" ]] || log::die "Missing --installer"
}

cc_cloud::verify_lightroom() {
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    log::info "verify.lightroom_exe=${LIGHTROOM_CC_EXE}"
    return 0
  fi
  [[ -f "${LIGHTROOM_CC_EXE}" ]] || log::die "Lightroom cloud executable not found after install: ${LIGHTROOM_CC_EXE}"
}

cc_cloud::install_bootstrapper() {
  fs::mkdir "${LIGHTROOM_CC_PREFIX}"
  fs::run env WINEPREFIX="${LIGHTROOM_CC_PREFIX}" WINEARCH=win64 wineboot --init
  fs::run env WINEPREFIX="${LIGHTROOM_CC_PREFIX}" wine "${LIGHTROOM_ARCH_INSTALLER}"
}

cc_cloud::main() {
  log::init
  cc_cloud::parse_args "$@"
  log::info "approach=wine-cc-cloud version=${LIGHTROOM_ARCH_VERSION}"
  log::info "prefix=${LIGHTROOM_CC_PREFIX}"
  log::info "expected_lightroom_exe=${LIGHTROOM_CC_EXE}"
  fs::require_file "${LIGHTROOM_ARCH_INSTALLER}"
  cc_cloud::install_bootstrapper
  cc_cloud::verify_lightroom
}

cc_cloud::main "$@"
