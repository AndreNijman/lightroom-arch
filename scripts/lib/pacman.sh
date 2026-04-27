#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

: "${LIGHTROOM_ARCH_DRY_RUN:=0}"
: "${LIGHTROOM_ARCH_NON_INTERACTIVE:=0}"

pacman::has_command() {
  command -v "$1" >/dev/null 2>&1
}

pacman::aur_helper() {
  if command -v yay >/dev/null 2>&1; then
    printf 'yay\n'
  elif command -v paru >/dev/null 2>&1; then
    printf 'paru\n'
  else
    printf 'none\n'
  fi
}

pacman::multilib_enabled() {
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*\[multilib\][[:space:]]*$/ { found=1 }
    END { exit found ? 0 : 1 }
  ' /etc/pacman.conf
}

pacman::enable_multilib() {
  local conf=/etc/pacman.conf
  # shellcheck disable=SC2310
  if pacman::multilib_enabled; then
    log::info "preflight.multilib=enabled"
    return 0
  fi
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    log::warn "preflight.multilib=disabled dry-run would enable [multilib] in ${conf}"
    return 0
  fi
  if [[ "${LIGHTROOM_ARCH_NON_INTERACTIVE}" == "1" ]]; then
    log::die "Pacman [multilib] repository is disabled"
  fi
  if prompt::confirm "Enable [multilib] in ${conf}?"; then
    local tmp
    tmp=$(mktemp)
    awk '
      BEGIN { in_multilib=0 }
      /^[[:space:]]*#\[multilib\][[:space:]]*$/ {
        print "[multilib]"
        in_multilib=1
        next
      }
      in_multilib == 1 && /^[[:space:]]*#Include[[:space:]]*=[[:space:]]*\/etc\/pacman.d\/mirrorlist/ {
        sub(/^[[:space:]]*#/, "")
        print
        in_multilib=0
        next
      }
      { print }
    ' "${conf}" > "${tmp}"
    fs::run sudo install -m 0644 "${tmp}" "${conf}"
    rm -f "${tmp}"
    fs::run sudo pacman -Syy
  else
    log::die "Pacman [multilib] is required for Wine packages"
  fi
}
