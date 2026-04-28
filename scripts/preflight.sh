#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"
# shellcheck source=./lib/fs.sh
source "${SCRIPT_DIR}/lib/fs.sh"

: "${LIGHTROOM_ARCH_NON_INTERACTIVE:=0}"

preflight::usage() {
  cat <<'USAGE'
Usage: scripts/preflight.sh [--non-interactive] [--dry-run]
USAGE
}

preflight::parse_args() {
  while (($#)); do
    case "$1" in
      --dry-run)
        export LIGHTROOM_ARCH_DRY_RUN=1
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
  if command -v "${command_name}" >/dev/null 2>&1; then
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

preflight::check_flathub() {
  if flatpak remotes --columns=name 2>/dev/null | grep -Fxq flathub; then
    log::info "preflight.flatpak.flathub=present"
    return 0
  fi
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    log::warn "preflight.flatpak.flathub=missing"
    return 0
  fi
  log::die "Flatpak remote 'flathub' is required for the Bottles approach"
}

preflight::check_bottles_installable() {
  if flatpak info com.usebottles.bottles >/dev/null 2>&1; then
    log::info "preflight.bottles.flatpak=installed"
    return 0
  fi
  if flatpak remote-ls flathub --app 2>/dev/null | grep -Fq 'com.usebottles.bottles'; then
    log::info "preflight.bottles.flatpak=installable"
    return 0
  fi
  if command -v bottles >/dev/null 2>&1; then
    log::warn "preflight.bottles.native=present flatpak_installable=unknown"
    return 0
  fi
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    log::warn "preflight.bottles.flatpak=not-verified"
    return 0
  fi
  log::die "Bottles Flatpak is not installed or visible from Flathub"
}

preflight::run() {
  local log_path
  local os_id
  preflight::check_os
  preflight::require_or_warn pacman pacman
  preflight::require_or_warn flatpak flatpak
  preflight::check_flathub
  preflight::check_bottles_installable
  os_id=$(preflight::os_release_id)
  log_path=$(log::path)
  log::info "preflight.summary={os:${os_id},log:${log_path},bottles:flatpak-preferred}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  preflight::parse_args "$@"
  log::init
  preflight::run
fi
