#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../.." && pwd)
IMAGE_NAME=lightroom-arch-smoke:latest

if ! command -v docker >/dev/null 2>&1; then
  printf 'Docker is required for the Arch container smoke test.\n' >&2
  exit 127
fi

docker build -t "${IMAGE_NAME}" -f "${SCRIPT_DIR}/Dockerfile" "${PROJECT_ROOT}"
docker run --rm \
  -e LIGHTROOM_ARCH_TEST_OUTPUT_DIR=/tmp/lightroom-arch-test-output \
  -v "${PROJECT_ROOT}:/work/lightroom-arch:ro" \
  "${IMAGE_NAME}"
