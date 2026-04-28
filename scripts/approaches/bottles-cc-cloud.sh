#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../.." && pwd)

for lib in "${PROJECT_ROOT}"/scripts/lib/*.sh; do
  # shellcheck source=/dev/null
  source "${lib}"
done

: "${BOTTLES_CC_BOTTLE:=LightroomCCCloud}"
: "${BOTTLES_CC_RUNNER:=caffe}"
: "${BOTTLES_CC_EXPECTED_EXE:=${HOME}/.var/app/com.usebottles.bottles/data/bottles/bottles/${BOTTLES_CC_BOTTLE}/drive_c/Program Files/Adobe/Adobe Lightroom/Lightroom.exe}"

LIGHTROOM_ARCH_INSTALLER=''
LIGHTROOM_ARCH_VERSION='cc-cloud'

bottles_cc::usage() {
  cat <<'USAGE'
Usage: scripts/approaches/bottles-cc-cloud.sh --installer PATH [--version cc-cloud] [--non-interactive] [--dry-run]
USAGE
}

bottles_cc::parse_args() {
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
        bottles_cc::usage
        exit 0
        ;;
      *)
        log::die "Unknown bottles-cc-cloud argument: $1"
        ;;
    esac
    shift
  done
  [[ -n "${LIGHTROOM_ARCH_INSTALLER}" ]] || log::die "Missing --installer"
}

bottles_cc::resolve_installer() {
  local path=$1
  if [[ -f "${path}" ]]; then
    printf '%s\n' "${path}"
    return 0
  fi
  if [[ -d "${path}" ]]; then
    local found
    found=$(find "${path}" -maxdepth 2 -type f -iname '*.exe' | sort | head -n 1)
    [[ -n "${found}" ]] || log::die "No Windows installer .exe found under ${path}"
    printf '%s\n' "${found}"
    return 0
  fi
  log::die "Installer path does not exist: ${path}"
}

bottles_cc::ensure_flatpak_bottles() {
  if flatpak info com.usebottles.bottles >/dev/null 2>&1; then
    log::info "bottles.installation=flatpak-installed"
    return 0
  fi
  log::info "bottles.installation=flatpak-install"
  fs::run flatpak install -y flathub com.usebottles.bottles
}

bottles_cc::run_cli() {
  fs::run flatpak run --command=bottles-cli com.usebottles.bottles "$@"
}

bottles_cc::create_bottle() {
  bottles_cc::run_cli new --bottle-name "${BOTTLES_CC_BOTTLE}" --environment application --runner "${BOTTLES_CC_RUNNER}" --arch win64
}

bottles_cc::install_dependencies() {
  bottles_cc::run_cli dependencies --bottle "${BOTTLES_CC_BOTTLE}" --install corefonts
  bottles_cc::run_cli dependencies --bottle "${BOTTLES_CC_BOTTLE}" --install vcredist2019
  bottles_cc::run_cli dependencies --bottle "${BOTTLES_CC_BOTTLE}" --install dotnet48
}

bottles_cc::set_windows_version() {
  bottles_cc::run_cli reg --bottle "${BOTTLES_CC_BOTTLE}" --key 'HKEY_CURRENT_USER\Software\Wine' --value Version --data win10
}

bottles_cc::run_bootstrapper() {
  local installer=$1
  bottles_cc::run_cli run --bottle "${BOTTLES_CC_BOTTLE}" --executable "${installer}"
}

bottles_cc::verify_lightroom() {
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    log::info "verify.lightroom_exe=${BOTTLES_CC_EXPECTED_EXE}"
    return 0
  fi
  [[ -f "${BOTTLES_CC_EXPECTED_EXE}" ]] || log::die "Lightroom cloud executable not found after install: ${BOTTLES_CC_EXPECTED_EXE}"
}

bottles_cc::main() {
  local installer
  log::init
  bottles_cc::parse_args "$@"
  fs::require_path "${LIGHTROOM_ARCH_INSTALLER}"
  installer=$(bottles_cc::resolve_installer "${LIGHTROOM_ARCH_INSTALLER}")
  log::info "approach=bottles-cc-cloud version=${LIGHTROOM_ARCH_VERSION}"
  log::info "installer=${installer}"
  log::info "bottle=${BOTTLES_CC_BOTTLE}"
  log::info "runner=${BOTTLES_CC_RUNNER}"
  log::info "expected_lightroom_exe=${BOTTLES_CC_EXPECTED_EXE}"
  bottles_cc::ensure_flatpak_bottles
  bottles_cc::create_bottle
  bottles_cc::install_dependencies
  bottles_cc::set_windows_version
  bottles_cc::run_bootstrapper "${installer}"
  bottles_cc::verify_lightroom
}

bottles_cc::main "$@"
