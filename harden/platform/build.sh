#!/usr/bin/env bash
set -euo pipefail

: "${PDK_ROOT:?Set PDK_ROOT to the directory containing sky130A}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

python3 -m librelane --docker-no-tty --dockerized \
  --pdk-root "$PDK_ROOT" --run-tag platform --force-run-dir --hide-progress-bar \
  harden/platform/config.json 2>&1 | tee harden/platform/build.log
