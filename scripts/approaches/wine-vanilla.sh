#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../.." && pwd)

for lib in "${PROJECT_ROOT}"/scripts/lib/*.sh; do
  # shellcheck source=/dev/null
  source "${lib}"
done

log::init
log::die "The vanilla Wine approach is reserved for a later branch and is not implemented yet."
