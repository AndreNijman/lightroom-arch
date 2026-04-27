#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)

for lib in "${SCRIPT_DIR}"/lib/*.sh; do
  # shellcheck source=/dev/null
  source "${lib}"
done

LIGHTROOM_ARCH_APPROACH='lutris'
LIGHTROOM_ARCH_VERSION=''
LIGHTROOM_ARCH_INSTALLER=''

install::usage() {
  cat <<'USAGE'
Usage: scripts/install.sh [--approach lutris] [--version VERSION] [--installer PATH] [--non-interactive] [--dry-run]
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
      --version)
        shift
        LIGHTROOM_ARCH_VERSION=${1:-}
        ;;
      --installer)
        shift
        LIGHTROOM_ARCH_INSTALLER=${1:-}
        ;;
      --dry-run)
        LIGHTROOM_ARCH_DRY_RUN=1
        ;;
      --non-interactive)
        LIGHTROOM_ARCH_NON_INTERACTIVE=1
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
  if [[ -z "${LIGHTROOM_ARCH_VERSION}" ]]; then
    LIGHTROOM_ARCH_VERSION=$(prompt::version)
  fi
  if [[ -z "${LIGHTROOM_ARCH_INSTALLER}" ]]; then
    LIGHTROOM_ARCH_INSTALLER=$(prompt::read_required "Lightroom installer path")
  fi
  fs::require_file "${LIGHTROOM_ARCH_INSTALLER}"
}

install::run_preflight() {
  log::info "install.phase=preflight"
  local args=()
  if [[ "${LIGHTROOM_ARCH_NON_INTERACTIVE}" == "1" ]]; then
    args+=(--non-interactive)
  fi
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    args+=(--dry-run)
  fi
  "${SCRIPT_DIR}/preflight.sh" "${args[@]}"
}

install::dispatch() {
  local approach_script="${SCRIPT_DIR}/approaches/${LIGHTROOM_ARCH_APPROACH}.sh"
  local args=(
    --version "${LIGHTROOM_ARCH_VERSION}"
    --installer "${LIGHTROOM_ARCH_INSTALLER}"
  )
  [[ -x "${approach_script}" ]] || log::die "Unknown or non-executable approach: ${LIGHTROOM_ARCH_APPROACH}"
  if [[ "${LIGHTROOM_ARCH_NON_INTERACTIVE}" == "1" ]]; then
    args+=(--non-interactive)
  fi
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    args+=(--dry-run)
  fi
  log::info "install.phase=approach approach=${LIGHTROOM_ARCH_APPROACH}"
  "${approach_script}" "${args[@]}"
}

install::smoke_test() {
  log::info "install.phase=smoke-test"
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    log::info "smoke.dry_run=passed"
    return 0
  fi
  "${PROJECT_ROOT}/tests/smoke.sh" --installed
}

install::next_steps() {
  local desktop_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/applications"
  local log_path
  log_path=$(log::path)
  log::info "install.phase=next-steps"
  printf '\nNext steps:\n'
  printf '  Desktop entry: %s/lightroom-arch.desktop\n' "${desktop_dir}"
  printf '  Log file: %s\n' "${log_path}"
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
  install::smoke_test
  install::next_steps
}

install::main "$@"
