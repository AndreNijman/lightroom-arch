#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../.." && pwd)

for lib in "${PROJECT_ROOT}"/scripts/lib/*.sh; do
  # shellcheck source=/dev/null
  source "${lib}"
done

: "${BOTTLES_CC_BOTTLE:=LightroomCCCloud}"
: "${BOTTLES_CC_RUNNER:=caffe-9.7}"
: "${BOTTLES_CC_DXVK:=dxvk-2.7.1}"
: "${BOTTLES_CC_VKD3D:=vkd3d-proton-3.0}"
: "${BOTTLES_CC_NVAPI:=dxvk-nvapi-v0.9.1}"
: "${BOTTLES_CC_LATENCYFLEX:=latencyflex-v0.1.1}"
: "${BOTTLES_CC_FLATPAK_APP:=com.usebottles.bottles}"
: "${BOTTLES_CC_DATA_HOME:=${HOME}/.var/app/${BOTTLES_CC_FLATPAK_APP}/data/bottles}"
: "${BOTTLES_CC_EXTRA_DEPS:=}"
: "${BOTTLES_CC_EXPECTED_EXE:=${HOME}/.var/app/com.usebottles.bottles/data/bottles/bottles/${BOTTLES_CC_BOTTLE}/drive_c/Program Files/Adobe/Adobe Lightroom/Lightroom.exe}"

LIGHTROOM_ARCH_INSTALLER=''
LIGHTROOM_ARCH_VERSION='cc-cloud'
BOTTLES_CC_ACCESSIBLE_INSTALLER=''

bottles_cc::usage() {
  cat <<'USAGE'
Usage: scripts/approaches/bottles-cc-cloud.sh --installer PATH [--version cc-cloud] [--non-interactive] [--dry-run]
USAGE
}

bottles_cc::parse_args() {
  while (($#)); do
    case "$1" in
      --installer)
        shift
        LIGHTROOM_ARCH_INSTALLER=${1:-}
        ;;
      --version)
        shift
        LIGHTROOM_ARCH_VERSION=${1:-}
        ;;
      --dry-run)
        export LIGHTROOM_ARCH_DRY_RUN=1
        ;;
      --non-interactive)
        export LIGHTROOM_ARCH_NON_INTERACTIVE=1
        ;;
      -h|--help)
        bottles_cc::usage
        exit 0
        ;;
      *)
        log::die "Unknown bottles-cc-cloud argument: $1"
        ;;
    esac
    shift
  done
  [[ -n "${LIGHTROOM_ARCH_INSTALLER}" ]] || log::die "Missing --installer"
}

bottles_cc::resolve_installer() {
  local path=$1
  if [[ -f "${path}" ]]; then
    printf '%s\n' "${path}"
    return 0
  fi
  if [[ -d "${path}" ]]; then
    local found
    found=$(find "${path}" -maxdepth 2 -type f -iname '*.exe' | sort | head -n 1)
    [[ -n "${found}" ]] || log::die "No Windows installer .exe found under ${path}"
    printf '%s\n' "${found}"
    return 0
  fi
  log::die "Installer path does not exist: ${path}"
}

bottles_cc::ensure_flatpak_bottles() {
  if flatpak info --user "${BOTTLES_CC_FLATPAK_APP}" >/dev/null 2>&1; then
    log::info "bottles.installation=flatpak-installed scope=user"
    return 0
  fi
  if flatpak info --system "${BOTTLES_CC_FLATPAK_APP}" >/dev/null 2>&1; then
    log::info "bottles.installation=flatpak-installed scope=system"
    return 0
  fi
  log::info "bottles.installation=flatpak-install scope=user"
  fs::run flatpak install --user -y flathub "${BOTTLES_CC_FLATPAK_APP}"
}

bottles_cc::flatpak_env() {
  local xdg_data_dirs="${HOME}/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
  local user_name
  local user_id
  user_name=${USER:-$(id -un)}
  user_id=$(id -u)
  env \
    HOME="${HOME}" \
    USER="${user_name}" \
    LOGNAME="${LOGNAME:-${user_name}}" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${user_id}}" \
    XDG_DATA_DIRS="${XDG_DATA_DIRS:-${xdg_data_dirs}}" \
    "$@"
}

bottles_cc::run_cli() {
  fs::run bottles_cc::flatpak_env flatpak run --command=bottles-cli "${BOTTLES_CC_FLATPAK_APP}" "$@"
}

bottles_cc::resolve_runner() {
  case "${BOTTLES_CC_RUNNER}" in
    caffe)
      BOTTLES_CC_RUNNER='caffe-9.7'
      ;;
    soda)
      BOTTLES_CC_RUNNER='soda-9.0-1'
      ;;
    *)
      ;;
  esac
}

bottles_cc::component_dir() {
  case "$1" in
    runner)
      printf '%s/runners\n' "${BOTTLES_CC_DATA_HOME}"
      ;;
    dxvk)
      printf '%s/dxvk\n' "${BOTTLES_CC_DATA_HOME}"
      ;;
    vkd3d)
      printf '%s/vkd3d\n' "${BOTTLES_CC_DATA_HOME}"
      ;;
    nvapi)
      printf '%s/nvapi\n' "${BOTTLES_CC_DATA_HOME}"
      ;;
    latencyflex)
      printf '%s/latencyflex\n' "${BOTTLES_CC_DATA_HOME}"
      ;;
    *)
      log::die "Unknown Bottles component category: $1"
      ;;
  esac
}

bottles_cc::download_component() {
  local category=$1
  local name=$2
  local archive=$3
  local url=$4
  local checksum=$5
  local install_dir
  local archive_path
  local root_dir
  local target_dir
  install_dir=$(bottles_cc::component_dir "${category}")
  archive_path="${BOTTLES_CC_DATA_HOME}/temp/${archive}"

  if [[ -d "${install_dir}/${name}" ]]; then
    log::info "bottles.component=${name} status=installed"
    return 0
  fi

  fs::mkdir "${install_dir}"
  fs::mkdir "${BOTTLES_CC_DATA_HOME}/temp"
  log::info "bottles.component=${name} status=download url=${url}"
  fs::run curl -fL --retry 2 --connect-timeout 20 -o "${archive_path}" "${url}"
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    return 0
  fi

  printf '%s  %s\n' "${checksum}" "${archive_path}" | md5sum -c -
  root_dir=$(tar -tf "${archive_path}" | sed -n '1p')
  root_dir=${root_dir%%/*}
  fs::run tar -xf "${archive_path}" -C "${install_dir}"
  target_dir=${root_dir%-x86_64}
  if [[ "${root_dir}" != "${target_dir}" && -d "${install_dir}/${root_dir}" && ! -e "${install_dir}/${target_dir}" ]]; then
    fs::run mv "${install_dir}/${root_dir}" "${install_dir}/${target_dir}"
  fi
  [[ -d "${install_dir}/${name}" ]] || log::die "Bottles component did not install to expected path: ${install_dir}/${name}"
}

bottles_cc::provision_components() {
  bottles_cc::resolve_runner
  case "${BOTTLES_CC_RUNNER}" in
    caffe-9.7)
      bottles_cc::download_component runner caffe-9.7 caffe-9.7-x86_64.tar.xz \
        https://github.com/bottlesdevs/wine/releases/download/caffe-9.7/caffe-9.7-x86_64.tar.xz \
        0cf8d63189771c05e1d94ce4a2d03931
      ;;
    soda-9.0-1)
      bottles_cc::download_component runner soda-9.0-1 soda-9.0-1-x86_64.tar.xz \
        https://github.com/bottlesdevs/wine/releases/download/soda-9.0-1/soda-9.0-1-x86_64.tar.xz \
        8806df3e294dd37cf461ed3432d65318
      ;;
    *)
      log::die "Unsupported Bottles CC runner: ${BOTTLES_CC_RUNNER}"
      ;;
  esac
  bottles_cc::download_component dxvk "${BOTTLES_CC_DXVK}" dxvk-2.7.1.tar.gz \
    https://github.com/doitsujin/dxvk/releases/download/v2.7.1/dxvk-2.7.1.tar.gz \
    b483fbc166963efba08eabbdf21586f0
  bottles_cc::download_component vkd3d "${BOTTLES_CC_VKD3D}" vkd3d-proton-3.0.tar.gz \
    https://github.com/bottlesdevs/components/releases/download/vkd3d-proton-3.0/vkd3d-proton-3.0.tar.gz \
    89493fae7e9a81958067a4e665269267
  bottles_cc::download_component nvapi "${BOTTLES_CC_NVAPI}" dxvk-nvapi-v0.9.1.tar.gz \
    https://github.com/bottlesdevs/components/releases/download/dxvk-nvapi-v0.9.1/dxvk-nvapi-v0.9.1.tar.gz \
    a7dae52a7ed8efe8c9be6a3dd7b2bab7
  bottles_cc::download_component latencyflex "${BOTTLES_CC_LATENCYFLEX}" latencyflex-v0.1.1.tar.xz \
    https://github.com/ishitatsuyuki/LatencyFleX/releases/download/v0.1.1/latencyflex-v0.1.1.tar.xz \
    599c3b183da35059f5b52d989665145a
}

bottles_cc::create_bottle() {
  if [[ -f "${BOTTLES_CC_DATA_HOME}/bottles/${BOTTLES_CC_BOTTLE}/bottle.yml" ]]; then
    log::info "bottle=${BOTTLES_CC_BOTTLE} status=exists"
    return 0
  fi
  bottles_cc::run_cli new \
    --bottle-name "${BOTTLES_CC_BOTTLE}" \
    --environment application \
    --runner "${BOTTLES_CC_RUNNER}" \
    --dxvk "${BOTTLES_CC_DXVK}" \
    --vkd3d "${BOTTLES_CC_VKD3D}" \
    --nvapi "${BOTTLES_CC_NVAPI}" \
    --latencyflex "${BOTTLES_CC_LATENCYFLEX}" \
    --arch win64
}

bottles_cc::install_dependencies() {
  log::info "bottles.dependencies=arial32,times32,courie32,vcredist2019,dotnet48 extra=${BOTTLES_CC_EXTRA_DEPS:-none} method=bottles-backend"
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    return 0
  fi
  BOTTLES_CC_EXTRA_DEPS="${BOTTLES_CC_EXTRA_DEPS}" bottles_cc::flatpak_env flatpak run --command=python3 "${BOTTLES_CC_FLATPAK_APP}" - "${BOTTLES_CC_BOTTLE}" <<'PY'
import os
import sys
import time
import urllib.request
import warnings

warnings.filterwarnings("ignore")
sys.path.insert(1, "/app/share/bottles")

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gio

from bottles.backend.managers.manager import Manager
from bottles.backend.utils import yaml
from bottles.frontend.params import APP_ID

bottle_name = sys.argv[1]
deps = ["arial32", "times32", "courie32", "vcredist2019", "dotnet48"]
extra_deps = [dep.strip() for dep in os.environ.get("BOTTLES_CC_EXTRA_DEPS", "").split(",") if dep.strip()]
deps.extend(dep for dep in extra_deps if dep not in deps)
manager = Manager(g_settings=Gio.Settings.new(APP_ID), is_cli=False)
time.sleep(3)
index = yaml.load(urllib.request.urlopen("https://proxy.usebottles.com/repo/dependencies/index.yml", timeout=30).read())
repo = manager.dependency_manager._DependencyManager__repo
repo.catalog = index
manager.supported_dependencies = index
manager.check_bottles()
if bottle_name not in manager.local_bottles:
    raise SystemExit(f"Bottle not found: {bottle_name}")
config = manager.local_bottles[bottle_name]
for dep in deps:
    if dep in config.Installed_Dependencies:
        print(f"dependency={dep} status=installed")
        continue
    if dep not in index:
        raise SystemExit(f"Dependency not in Bottles repository: {dep}")
    result = manager.dependency_manager.install(config, [dep, index[dep]])
    if not result.ok:
        raise SystemExit(f"Dependency install failed: {dep} {result.message}")
    print(f"dependency={dep} status=installed")
PY
}

bottles_cc::set_windows_version() {
  bottles_cc::run_cli edit -b "${BOTTLES_CC_BOTTLE}" --win win10
}

bottles_cc::stage_installer() {
  local installer=$1
  local destination_dir="${BOTTLES_CC_DATA_HOME}/temp/lightroom-arch-installers"
  local destination
  destination="${destination_dir}/$(basename -- "${installer}")"
  if [[ "${installer}" == "${BOTTLES_CC_DATA_HOME}"/* ]]; then
    BOTTLES_CC_ACCESSIBLE_INSTALLER=${installer}
    return 0
  fi
  fs::mkdir "${destination_dir}"
  fs::run cp -f -- "${installer}" "${destination}"
  BOTTLES_CC_ACCESSIBLE_INSTALLER=${destination}
  log::info "installer.staged=${BOTTLES_CC_ACCESSIBLE_INSTALLER}"
}

bottles_cc::run_bootstrapper() {
  local installer=$1
  bottles_cc::stage_installer "${installer}"
  bottles_cc::run_cli run -b "${BOTTLES_CC_BOTTLE}" -e "${BOTTLES_CC_ACCESSIBLE_INSTALLER}"
}

bottles_cc::verify_lightroom() {
  if [[ "${LIGHTROOM_ARCH_DRY_RUN}" == "1" ]]; then
    log::info "verify.lightroom_exe=${BOTTLES_CC_EXPECTED_EXE}"
    return 0
  fi
  [[ -f "${BOTTLES_CC_EXPECTED_EXE}" ]] || log::die "Lightroom cloud executable not found after install: ${BOTTLES_CC_EXPECTED_EXE}"
}

bottles_cc::main() {
  local installer
  log::init
  bottles_cc::parse_args "$@"
  fs::require_path "${LIGHTROOM_ARCH_INSTALLER}"
  installer=$(bottles_cc::resolve_installer "${LIGHTROOM_ARCH_INSTALLER}")
  log::info "approach=bottles-cc-cloud version=${LIGHTROOM_ARCH_VERSION}"
  log::info "installer=${installer}"
  log::info "bottle=${BOTTLES_CC_BOTTLE}"
  log::info "runner=${BOTTLES_CC_RUNNER}"
  log::info "expected_lightroom_exe=${BOTTLES_CC_EXPECTED_EXE}"
  bottles_cc::ensure_flatpak_bottles
  bottles_cc::provision_components
  bottles_cc::create_bottle
  bottles_cc::install_dependencies
  bottles_cc::set_windows_version
  bottles_cc::run_bootstrapper "${installer}"
  bottles_cc::verify_lightroom
}

bottles_cc::main "$@"
