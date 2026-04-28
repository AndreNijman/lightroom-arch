#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

for lib in "${SCRIPT_DIR}"/lib/*.sh; do
  # shellcheck source=/dev/null
  source "${lib}"
done

LIGHTROOM_ARCH_APPROACH='wine-cc-cloud'
LIGHTROOM_ARCH_INSTALLER=''
LIGHTROOM_ARCH_VERSION='cc-cloud'

install::usage() {
  cat <<'USAGE'
Usage: scripts/install.sh [--approach wine-cc-cloud] [--installer PATH] [--version VERSION] [--non-interactive] [--dry-run]
USAGE
}

install::on_error() {
  local exit_code=$?
  local log_path
  log_path=$(log::path)
  log::error "Install failed with exit code ${exit_code}. Log: ${log_path}"
  exit "${exit_code}"
}

install::parse_args() {
  while (($#)); do
    case "$1" in
      --approach)
        shift
        LIGHTROOM_ARCH_APPROACH=${1:-}
        ;;
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
        install::usage
        exit 0
        ;;
      *)
        log::die "Unknown install argument: $1"
        ;;
    esac
    shift
  done
}

install::resolve_inputs() {
  [[ -n "${LIGHTROOM_ARCH_INSTALLER}" ]] || log::die "Missing --installer"
  fs::require_file "${LIGHTROOM_ARCH_INSTALLER}"
}

install::run_preflight() {
  local args=()
  log::info "install.phase=preflight"
  if [[ "${LIGHTROOM_ARCH_NON_INTERACTIVE:-0}" == "1" ]]; then
    args+=(--non-interactive)
  fi
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    args+=(--dry-run)
  fi
  "${SCRIPT_DIR}/preflight.sh" "${args[@]}"
}

install::dispatch() {
  local approach_script="${SCRIPT_DIR}/approaches/${LIGHTROOM_ARCH_APPROACH}.sh"
  local args=(--installer "${LIGHTROOM_ARCH_INSTALLER}" --version "${LIGHTROOM_ARCH_VERSION}")
  [[ -x "${approach_script}" ]] || log::die "Unknown or non-executable approach: ${LIGHTROOM_ARCH_APPROACH}"
  if [[ "${LIGHTROOM_ARCH_NON_INTERACTIVE:-0}" == "1" ]]; then
    args+=(--non-interactive)
  fi
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    args+=(--dry-run)
  fi
  log::info "install.phase=approach approach=${LIGHTROOM_ARCH_APPROACH}"
  "${approach_script}" "${args[@]}"
}

install::main() {
  log::init
  trap install::on_error ERR
  install::parse_args "$@"
  export LIGHTROOM_ARCH_LOG_DIR
  export LIGHTROOM_ARCH_LOG_PATH
  export LIGHTROOM_ARCH_DRY_RUN
  export LIGHTROOM_ARCH_NON_INTERACTIVE
  install::resolve_inputs
  install::run_preflight
  install::dispatch
}

install::main "$@"
