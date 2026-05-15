#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Lightroom Classic via PhialsBasement patched Wine + official CC installer.
# Requires: active Adobe CC subscription, patched Wine at ~/opt/wine-adobe.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "${SCRIPT_DIR}/../.." && pwd)

# shellcheck source=../lib/log.sh
source "${SCRIPT_DIR}/../lib/log.sh"
# shellcheck source=../lib/fs.sh
source "${SCRIPT_DIR}/../lib/fs.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"

WINE_ADOBE_DIR="${HOME}/opt/wine-adobe/files"
WINEPREFIX="${HOME}/.wine_adobe"
WINEARCH="win64"
CC_INSTALLER_URL="https://creativecloud.adobe.com/apps/download/creative-cloud"

export WINEPREFIX WINEARCH

wine_adobe() {
  PATH="${WINE_ADOBE_DIR}/bin:${PATH}" "$@"
}

step::check_patched_wine() {
  log::info "step.check_patched_wine"
  if [[ ! -x "${WINE_ADOBE_DIR}/bin/wine" ]]; then
    log::die "Patched Wine not found at ${WINE_ADOBE_DIR}/bin/wine. Run setup first."
  fi
  local version
  version=$(wine_adobe wine --version 2>/dev/null || true)
  log::info "patched_wine.version=${version}"
}

step::check_system_deps() {
  log::info "step.check_system_deps"
  local missing=()
  local pkgs=(
    wine-staging winetricks
    lib32-gnutls lib32-alsa-lib lib32-alsa-plugins
    lib32-libpulse lib32-openal lib32-mpg123
    lib32-libxcomposite lib32-libxinerama lib32-ncurses
    lib32-opencl-icd-loader lib32-libxslt lib32-libva
    lib32-gtk3 lib32-vulkan-icd-loader
    lib32-giflib lib32-libpng lib32-libjpeg-turbo
    cups samba dosbox
  )
  for pkg in "${pkgs[@]}"; do
    if ! pacman -Q "${pkg}" >/dev/null 2>&1; then
      missing+=("${pkg}")
    fi
  done
  if ((${#missing[@]} > 0)); then
    log::warn "missing_packages=${missing[*]}"
    log::info "Install with: sudo pacman -S ${missing[*]}"
    if prompt::confirm "Install missing packages now?"; then
      fs::run sudo pacman -S --needed "${missing[@]}"
    else
      log::warn "Continuing without installing. Some features may not work."
    fi
  else
    log::info "system_deps=all_present"
  fi
}

step::init_prefix() {
  log::info "step.init_prefix wineprefix=${WINEPREFIX}"
  if [[ -d "${WINEPREFIX}" ]]; then
    if prompt::confirm "Wine prefix exists at ${WINEPREFIX}. Delete and recreate?"; then
      fs::remove_path "${WINEPREFIX}"
    else
      log::info "prefix.reuse=true"
      return 0
    fi
  fi
  wine_adobe wine wineboot --init 2>&1 | tee -a "$(log::path)" || true
  wine_adobe wineserver -w 2>/dev/null || true
  log::info "prefix.created=${WINEPREFIX}"
}

step::set_windows_version() {
  log::info "step.set_windows_version target=win7"
  wine_adobe wine reg add 'HKCU\Software\Wine' /v Version /t REG_SZ /d win7 /f 2>&1 | tee -a "$(log::path)" || true
  log::info "windows_version=win7"
}

step::install_winetricks_deps() {
  log::info "step.install_winetricks_deps"
  local tricks=(atmlib gdiplus msxml3 msxml6 vcrun2017 corefonts)
  for trick in "${tricks[@]}"; do
    log::info "winetricks.install=${trick}"
    WINE="${WINE_ADOBE_DIR}/bin/wine" wine_adobe winetricks -q "${trick}" 2>&1 | tee -a "$(log::path)" || {
      log::warn "winetricks.${trick}=failed (non-fatal, continuing)"
    }
  done
  log::info "winetricks.complete"
}

step::download_cc_installer() {
  log::info "step.download_cc_installer"
  local installer_dir="${REPO_DIR}/installers"
  local installer_exe="${installer_dir}/Creative_Cloud_Set-Up.exe"
  fs::mkdir "${installer_dir}"

  if [[ -f "${installer_exe}" ]]; then
    log::info "cc_installer.exists=${installer_exe}"
    return 0
  fi

  log::info "cc_installer.download_required"
  printf '\n'
  printf '═══════════════════════════════════════════════════════════\n'
  printf ' Manual download required:\n'
  printf ' 1. Open: https://creativecloud.adobe.com/apps/download/creative-cloud\n'
  printf ' 2. Download the Windows installer (Creative_Cloud_Set-Up.exe)\n'
  printf ' 3. Save to: %s\n' "${installer_exe}"
  printf '═══════════════════════════════════════════════════════════\n'
  printf '\n'

  if [[ "${LIGHTROOM_ARCH_NON_INTERACTIVE:-0}" == "1" ]]; then
    log::die "CC installer not found and running non-interactive"
  fi

  read -r -p "Press Enter once the installer is saved..."
  fs::require_file "${installer_exe}"
}

step::run_cc_installer() {
  log::info "step.run_cc_installer"
  local installer_exe="${REPO_DIR}/installers/Creative_Cloud_Set-Up.exe"
  fs::require_file "${installer_exe}"

  log::info "cc_installer.launching"
  printf '\n'
  printf '═══════════════════════════════════════════════════════════\n'
  printf ' Launching Creative Cloud installer via patched Wine.\n'
  printf ' - Installer may pause at 81%% and 97%% — this is normal.\n'
  printf ' - A browser window will open for Adobe login.\n'
  printf ' - Login with your CC account.\n'
  printf ' - After CC Desktop installs, use it to install Lightroom Classic.\n'
  printf '═══════════════════════════════════════════════════════════\n'
  printf '\n'

  wine_adobe wine "${installer_exe}" 2>&1 | tee -a "$(log::path)" || {
    log::error "cc_installer.exit_code=$?"
    log::info "Check log: $(log::path)"
  }

  log::info "cc_installer.finished"
}

step::launch_cc_desktop() {
  log::info "step.launch_cc_desktop"
  local cc_exe="${WINEPREFIX}/drive_c/Program Files (x86)/Adobe/Adobe Creative Cloud/ACC/Creative Cloud.exe"
  if [[ ! -f "${cc_exe}" ]]; then
    cc_exe="${WINEPREFIX}/drive_c/Program Files/Adobe/Adobe Creative Cloud/ACC/Creative Cloud.exe"
  fi
  if [[ ! -f "${cc_exe}" ]]; then
    log::warn "CC Desktop not found at expected paths. Searching..."
    local found
    found=$(find "${WINEPREFIX}" -name "Creative Cloud.exe" -type f 2>/dev/null | head -1 || true)
    if [[ -n "${found}" ]]; then
      cc_exe="${found}"
      log::info "cc_desktop.found=${cc_exe}"
    else
      log::die "Creative Cloud Desktop not found in prefix. Installation may have failed."
    fi
  fi
  log::info "cc_desktop.launching=${cc_exe}"
  wine_adobe wine "${cc_exe}" 2>&1 | tee -a "$(log::path)" &
  log::info "cc_desktop.launched_bg"
}

main() {
  log::init
  log::info "=== Lightroom Classic via Patched Wine CC Installer ==="
  log::info "date=$(date -Iseconds)"
  log::info "kernel=$(uname -r)"
  log::info "wineprefix=${WINEPREFIX}"

  step::check_patched_wine
  step::check_system_deps
  step::init_prefix
  step::set_windows_version
  step::install_winetricks_deps
  step::download_cc_installer
  step::run_cc_installer
  step::launch_cc_desktop

  printf '\n'
  printf '═══════════════════════════════════════════════════════════\n'
  printf ' CC Desktop should be running. Install Lightroom Classic\n'
  printf ' from the Apps tab.\n'
  printf '═══════════════════════════════════════════════════════════\n'
  printf '\n'
  log::info "=== Done ==="
}

main "$@"
