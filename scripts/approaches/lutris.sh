#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../.." && pwd)

for lib in "${PROJECT_ROOT}"/scripts/lib/*.sh; do
  # shellcheck source=/dev/null
  source "${lib}"
done

LIGHTROOM_ARCH_VERSION=''
LIGHTROOM_ARCH_INSTALLER=''

lutris::usage() {
  cat <<'USAGE'
Usage: scripts/approaches/lutris.sh --version VERSION --installer PATH [--non-interactive] [--dry-run]
USAGE
}

lutris::parse_args() {
  while (($#)); do
    case "$1" in
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
        export LIGHTROOM_ARCH_NON_INTERACTIVE=1
        ;;
      -h|--help)
        lutris::usage
        exit 0
        ;;
      *)
        log::die "Unknown lutris argument: $1"
        ;;
    esac
    shift
  done
  [[ -n "${LIGHTROOM_ARCH_VERSION}" ]] || log::die "Missing --version"
  [[ -n "${LIGHTROOM_ARCH_INSTALLER}" ]] || log::die "Missing --installer"
}

lutris::prefix_name() {
  printf 'lightroom-%s\n' "${LIGHTROOM_ARCH_VERSION//[^[:alnum:]._-]/-}"
}

lutris::prefix_path() {
  local prefix_name
  prefix_name=$(lutris::prefix_name)
  printf '%s/prefixes/%s\n' "${XDG_DATA_HOME:-${HOME}/.local/share}/lightroom-arch" "${prefix_name}"
}

lutris::install_dependencies() {
  local prefix=$1
  fs::run env WINEPREFIX="${prefix}" WINEARCH=win64 wineboot --init
  fs::run env WINEPREFIX="${prefix}" wine reg add 'HKCU\Software\Wine' /v Version /d win7 /f
  fs::run env WINEPREFIX="${prefix}" winetricks -q gdiplus windowscodecs corefonts
}

lutris::install_color_profile() {
  local prefix=$1
  local target="${prefix}/drive_c/windows/system32/spool/drivers/color/sRGB ColorSpace Profile.icm"
  local source_profile=''
  local candidate
  for candidate in \
    /usr/share/color/icc/colord/sRGB.icc \
    /usr/share/color/icc/sRGB.icc \
    /usr/share/color/icc/Argyll/sRGB.icm; do
    if [[ -f "${candidate}" ]]; then
      source_profile=${candidate}
      break
    fi
  done
  if [[ -z "${source_profile}" && "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    source_profile=/usr/share/color/icc/colord/sRGB.icc
  fi
  [[ -n "${source_profile}" ]] || log::die "No sRGB ICC profile found"
  fs::mkdir "$(dirname -- "${target}")"
  fs::copy "${source_profile}" "${target}"
}

lutris::default_lightroom_exe() {
  local prefix=$1
  printf '%s\n' "${prefix}/drive_c/Program Files/Adobe/Adobe Photoshop Lightroom/lightroom.exe"
}

lutris::verify_install() {
  local prefix=$1
  local exe_path
  exe_path=$(lutris::default_lightroom_exe "${prefix}")
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    log::info "verify.lightroom_exe=${exe_path}"
    return 0
  fi
  [[ -f "${exe_path}" ]] || log::die "Lightroom executable not found after install: ${exe_path}"
}

lutris::desktop_entry() {
  local prefix=$1
  local exe_path
  exe_path=$(lutris::default_lightroom_exe "${prefix}")
  local desktop_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/applications"
  local desktop_file="${desktop_dir}/lightroom-arch.desktop"
  fs::mkdir "${desktop_dir}"
  fs::write_file "${desktop_file}" "[Desktop Entry]
Type=Application
Name=Adobe Lightroom (Wine)
Comment=Run Adobe Lightroom through lightroom-arch
Exec=env WINEPREFIX=${prefix} wine \"${exe_path}\"
Terminal=false
Categories=Graphics;Photography;"
  if command -v update-desktop-database >/dev/null 2>&1; then
    fs::run update-desktop-database "${desktop_dir}"
  fi
  log::info "desktop.entry=${desktop_file}"
}

lutris::run_installer() {
  local prefix=$1
  fs::require_file "${LIGHTROOM_ARCH_INSTALLER}"
  fs::run env WINEPREFIX="${prefix}" wine "${LIGHTROOM_ARCH_INSTALLER}"
}

lutris::main() {
  log::init
  lutris::parse_args "$@"
  log::info "approach=lutris version=${LIGHTROOM_ARCH_VERSION}"
  local prefix
  prefix=$(lutris::prefix_path)
  fs::mkdir "${prefix}"
  lutris::install_dependencies "${prefix}"
  lutris::install_color_profile "${prefix}"
  lutris::run_installer "${prefix}"
  lutris::verify_install "${prefix}"
  lutris::desktop_entry "${prefix}"
  log::info "approach.lutris.complete prefix=${prefix}"
}

lutris::main "$@"
