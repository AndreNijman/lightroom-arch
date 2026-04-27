#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"
# shellcheck source=./lib/fs.sh
source "${SCRIPT_DIR}/lib/fs.sh"
# shellcheck source=./lib/prompt.sh
source "${SCRIPT_DIR}/lib/prompt.sh"
# shellcheck source=./lib/pacman.sh
source "${SCRIPT_DIR}/lib/pacman.sh"
# shellcheck source=./lib/gpu.sh
source "${SCRIPT_DIR}/lib/gpu.sh"

preflight::usage() {
  cat <<'USAGE'
Usage: scripts/preflight.sh [--non-interactive] [--dry-run]
USAGE
}

preflight::parse_args() {
  while (($#)); do
    case "$1" in
      --dry-run)
        LIGHTROOM_ARCH_DRY_RUN=1
        ;;
      --non-interactive)
        export LIGHTROOM_ARCH_NON_INTERACTIVE=1
        ;;
      -h|--help)
        preflight::usage
        exit 0
        ;;
      *)
        log::die "Unknown preflight argument: $1"
        ;;
    esac
    shift
  done
}

preflight::require_or_warn() {
  local command_name=$1
  local package_hint=$2
  if pacman::has_command "${command_name}"; then
    log::info "preflight.command.${command_name}=present"
    return 0
  fi
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    log::warn "preflight.command.${command_name}=missing package=${package_hint}"
    return 0
  fi
  log::die "Required command missing: ${command_name} (install ${package_hint})"
}

preflight::os_release_id() {
  local id='unknown'
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    id=${ID:-unknown}
  fi
  printf '%s\n' "${id}"
}

preflight::check_os() {
  local id
  id=$(preflight::os_release_id)
  case "${id}" in
    arch|endeavouros|cachyos)
      log::info "preflight.os=${id}"
      ;;
    *)
      if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
        log::warn "preflight.os=${id} unsupported"
      else
        log::die "Unsupported distro ID '${id}'. Supported: arch, endeavouros, cachyos"
      fi
      ;;
  esac
}

preflight::check_disk() {
  local available_kb
  available_kb=$(df -Pk "${HOME}" | awk 'NR == 2 { print $4 }')
  local required_kb=$((10 * 1024 * 1024))
  if ((available_kb >= required_kb)); then
    log::info "preflight.disk.home.available_kb=${available_kb}"
    return 0
  fi
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    log::warn "preflight.disk.home.available_kb=${available_kb} required_kb=${required_kb}"
    return 0
  fi
  log::die "At least 10GB free space is required on HOME"
}

preflight::run() {
  local aur_helper
  local gpu_summary
  local log_path
  local os_id
  preflight::check_os
  preflight::require_or_warn pacman pacman
  pacman::enable_multilib
  preflight::check_disk
  gpu_summary=$(gpu::summary)
  log::info "preflight.gpu.${gpu_summary}"
  preflight::require_or_warn wine wine
  preflight::require_or_warn winetricks winetricks
  aur_helper=$(pacman::aur_helper)
  os_id=$(preflight::os_release_id)
  log_path=$(log::path)
  log::info "preflight.aur_helper=${aur_helper}"
  log::info "preflight.summary={os:${os_id},aur:${aur_helper},log:${log_path}}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  preflight::parse_args "$@"
  log::init
  preflight::run
fi
