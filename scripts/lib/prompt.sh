#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

: "${LIGHTROOM_ARCH_NON_INTERACTIVE:=0}"

prompt::read_required() {
  local label=$1
  local value
  if [[ "${LIGHTROOM_ARCH_NON_INTERACTIVE}" == "1" ]]; then
    log::die "Missing required value in --non-interactive mode: ${label}"
  fi
  read -r -p "${label}: " value
  [[ -n "${value}" ]] || log::die "A value is required for ${label}"
  printf '%s\n' "${value}"
}

prompt::confirm() {
  local message=$1
  local answer
  if [[ "${LIGHTROOM_ARCH_NON_INTERACTIVE}" == "1" ]]; then
    return 1
  fi
  read -r -p "${message} [y/N]: " answer
  [[ "${answer}" == "y" || "${answer}" == "Y" ]]
}

prompt::version() {
  local value
  if [[ "${LIGHTROOM_ARCH_NON_INTERACTIVE}" == "1" ]]; then
    log::die "Missing --version in --non-interactive mode"
  fi
  printf 'Supported target versions:\n'
  printf '  1. Lightroom 5.7.1 (primary)\n'
  printf '  2. Lightroom 6.14 (fallback)\n'
  read -r -p "Choose version [5.7.1]: " value
  printf '%s\n' "${value:-5.7.1}"
}
