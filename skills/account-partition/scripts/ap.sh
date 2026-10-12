#!/usr/bin/env bash
# aplib.py CLI 진입점 (멀티 OS). 사용법은 `bash ap.sh` 또는 aplib.py docstring 참조.
#   ap.sh targets | accounts | plan-add ... | plan-adopt ... | plan-unlink ... | env <name> | run <name> -- <cmd>
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/platform.sh"
exec "$AP_PYTHON" "$AP_LIB" "$@"
