#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

for lib in "${SCRIPT_DIR}"/lib/*.sh; do
  # shellcheck source=/dev/null
  source "${lib}"
done

LIGHTROOM_ARCH_PURGE=0

uninstall::usage() {
  cat <<'USAGE'
Usage: scripts/uninstall.sh [--purge] [--non-interactive] [--dry-run]
USAGE
}

uninstall::parse_args() {
  while (($#)); do
    case "$1" in
      --purge)
        LIGHTROOM_ARCH_PURGE=1
        ;;
      --dry-run)
        export LIGHTROOM_ARCH_DRY_RUN=1
        ;;
      --non-interactive)
        export LIGHTROOM_ARCH_NON_INTERACTIVE=1
        ;;
      -h|--help)
        uninstall::usage
        exit 0
        ;;
      *)
        log::die "Unknown uninstall argument: $1"
        ;;
    esac
    shift
  done
}

uninstall::main() {
  log::init
  uninstall::parse_args "$@"
  local data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/lightroom-arch"
  local desktop_entry="${XDG_DATA_HOME:-${HOME}/.local/share}/applications/lightroom-arch.desktop"
  local mime_entry="${XDG_DATA_HOME:-${HOME}/.local/share}/mime/packages/lightroom-arch.xml"
  fs::remove_path "${data_dir}/prefixes"
  fs::remove_path "${desktop_entry}"
  fs::remove_path "${mime_entry}"
  if [[ "${LIGHTROOM_ARCH_PURGE}" == "1" ]]; then
    fs::remove_path "${data_dir}"
    log::warn "uninstall.purge=removed-catalogs-and-user-data-under-${data_dir}"
  else
    log::info "uninstall.preserve=${data_dir}/catalogs"
  fi
  if command -v update-desktop-database >/dev/null 2>&1; then
    fs::run update-desktop-database "${XDG_DATA_HOME:-${HOME}/.local/share}/applications"
  fi
  if command -v update-mime-database >/dev/null 2>&1; then
    fs::run update-mime-database "${XDG_DATA_HOME:-${HOME}/.local/share}/mime"
  fi
  local log_path
  log_path=$(log::path)
  log::info "uninstall.complete log=${log_path}"
}

uninstall::main "$@"
