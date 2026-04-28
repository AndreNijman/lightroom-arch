#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

gpu::summary() {
  local lspci_output='unavailable'
  local vendor='unknown'
  local driver='unknown'
  if command -v lspci >/dev/null 2>&1; then
    lspci_output=$(lspci -nn | awk '/VGA|3D|Display/ { print }')
  fi
  case "${lspci_output,,}" in
    *nvidia*) vendor='nvidia' ;;
    *amd*|*ati*) vendor='amd' ;;
    *intel*) vendor='intel' ;;
    *) ;;
  esac
  if pacman -Q nvidia-utils >/dev/null 2>&1; then
    driver='nvidia-proprietary'
  elif pacman -Q mesa >/dev/null 2>&1; then
    driver='mesa'
  fi
  printf 'vendor=%s driver=%s devices=%s\n' "${vendor}" "${driver}" "${lspci_output}"
}
