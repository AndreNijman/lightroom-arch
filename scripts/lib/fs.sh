#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

: "${LIGHTROOM_ARCH_DRY_RUN:=0}"

fs::render_command() {
  local rendered=''
  local arg
  for arg in "$@"; do
    local quoted
    printf -v quoted '%q' "${arg}"
    rendered+="${quoted} "
  done
  printf '%s\n' "${rendered% }"
}

fs::run() {
  local rendered
  rendered=$(fs::render_command "$@")
  log::info "run: ${rendered}"
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    return 0
  fi
  "$@"
}

fs::mkdir() {
  log::info "mkdir: $1"
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    return 0
  fi
  mkdir -p "$1"
}

fs::require_path() {
  local path=$1
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    log::info "dry-run accepts path: ${path}"
    return 0
  fi
  [[ -e "${path}" ]] || log::die "Required path not found: ${path}"
}

fs::require_file() {
  local path=$1
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    log::info "dry-run accepts file path: ${path}"
    return 0
  fi
  [[ -f "${path}" ]] || log::die "Required file not found: ${path}"
}
