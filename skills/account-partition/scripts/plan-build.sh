#!/usr/bin/env bash
# 액션별 plan JSON 빌더.
set -uo pipefail

build_add() {
  local name="$1" config_dir="$2" shared_pool="$3"
  local shell_rc="$4" shell_mode="$5" shared_csv="$6"

  NAME="$name" CONFIG_DIR="$config_dir" SHARED_POOL="$shared_pool" \
  SHELL_RC="$shell_rc" SHELL_MODE="$shell_mode" SHARED_CSV="$shared_csv" \
  python3 <<'PYEOF'
import json, os
name = os.environ["NAME"]
config_dir = os.environ["CONFIG_DIR"]
shared_pool = os.environ["SHARED_POOL"]
shell_rc = os.environ["SHELL_RC"]
shell_mode = os.environ["SHELL_MODE"]
shared = [s for s in os.environ["SHARED_CSV"].split(",") if s]

# settings.json은 절대 포함 금지 (격리 강제)
shared = [s for s in shared if s != "settings.json"]

ops = []
ops.append({"op": "create_dir", "path": config_dir, "mode": "0700"})
ops.append({"op": "create_dir", "path": shared_pool, "mode": "0755"})

DIR_ITEMS = {"plugins", "skills", "commands", "agents"}

for item in shared:
    src = f"{shared_pool}/{item}"
    dst = f"{config_dir}/{item}"
    if item in DIR_ITEMS:
        ops.append({"op": "create_dir", "path": src, "mode": "0755"})
    ops.append({"op": "create_symlink", "src": src, "dst": dst, "backup_if_exists": True})

if shell_mode == "auto":
    home = os.environ.get("HOME", "")
    cd_disp = config_dir.replace(home, "$HOME") if home and config_dir.startswith(home) else config_dir
    ops.append({
        "op": "append_block",
        "file": shell_rc,
        "marker": f"# account-partition: {name}",
        "lines": [f'alias claude-{name}="CLAUDE_CONFIG_DIR={cd_disp} command claude"'],
        "backup": True,
    })

plan = {
    "metadata": {
        "action": "add",
        "alias_name": name,
        "config_dir": config_dir,
        "shared_pool": shared_pool,
        "shell_mode": shell_mode,
    },
    "preconditions": [
        {"check": "no_active_session", "config_dir": config_dir},
        {"check": "dir_absent", "path": config_dir},
    ],
    "operations": ops,
}
print(json.dumps(plan, ensure_ascii=False, indent=2))
PYEOF
}

build_unlink() {
  local name="$1" config_dir="$2" shell_rc="$3" shell_mode="$4"

  NAME="$name" CONFIG_DIR="$config_dir" \
  SHELL_RC="$shell_rc" SHELL_MODE="$shell_mode" \
  python3 <<'PYEOF'
import json, os
name = os.environ["NAME"]
config_dir = os.environ["CONFIG_DIR"]
shell_rc = os.environ["SHELL_RC"]
shell_mode = os.environ["SHELL_MODE"]

ops = []

# auth_logout은 shell-mode와 무관하게 항상 포함 (OAuth 정리는 idempotent·안전)
ops.append({"op": "auth_logout", "config_dir": config_dir})

if shell_mode == "auto":
    ops.append({
        "op": "remove_block",
        "file": shell_rc,
        "marker": f"# account-partition: {name}",
    })

ops.append({
    "op": "archive_dir",
    "src": config_dir,
    "remove_after": True,
})

plan = {
    "metadata": {
        "action": "unlink",
        "alias_name": name,
        "config_dir": config_dir,
        "shell_mode": shell_mode,
    },
    "preconditions": [
        {"check": "no_active_session", "config_dir": config_dir},
    ],
    "operations": ops,
}
print(json.dumps(plan, ensure_ascii=False, indent=2))
PYEOF
}

build_edit() {
  local name="$1" config_dir="$2" shared_pool="$3"
  local add_shared="$4" remove_shared="$5"

  NAME="$name" CONFIG_DIR="$config_dir" SHARED_POOL="$shared_pool" \
  ADD_SHARED="$add_shared" REMOVE_SHARED="$remove_shared" \
  python3 <<'PYEOF'
import json, os
name = os.environ["NAME"]
config_dir = os.environ["CONFIG_DIR"]
shared_pool = os.environ["SHARED_POOL"]
add_shared = [s for s in os.environ["ADD_SHARED"].split(",") if s]
remove_shared = [s for s in os.environ["REMOVE_SHARED"].split(",") if s]

# settings.json 금지
add_shared = [s for s in add_shared if s != "settings.json"]
remove_shared = [s for s in remove_shared if s != "settings.json"]

ops = []
for item in add_shared:
    src = f"{shared_pool}/{item}"
    dst = f"{config_dir}/{item}"
    ops.append({"op": "quarantine", "path": dst, "config_dir": config_dir})
    ops.append({"op": "create_symlink", "src": src, "dst": dst, "backup_if_exists": True})

for item in remove_shared:
    src = f"{shared_pool}/{item}"
    dst = f"{config_dir}/{item}"
    ops.append({"op": "remove_symlink", "dst": dst})
    ops.append({"op": "copy", "src": src, "dst": dst})

plan = {
    "metadata": {
        "action": "edit",
        "alias_name": name,
        "config_dir": config_dir,
        "shared_pool": shared_pool,
    },
    "preconditions": [
        {"check": "no_active_session", "config_dir": config_dir},
    ],
    "operations": ops,
}
print(json.dumps(plan, ensure_ascii=False, indent=2))
PYEOF
}

cmd="${1:-help}"
shift || true

# bash 3.2 호환 옵션 파싱 (declare -A 미지원)
opt_name=""
opt_config_dir=""
opt_shared_pool=""
opt_shell_rc=""
opt_shell_mode=""
opt_shared=""
opt_add_shared=""
opt_remove_shared=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)         opt_name="${2:-}";        shift 2 ;;
    --config-dir)   opt_config_dir="${2:-}";  shift 2 ;;
    --shared-pool)  opt_shared_pool="${2:-}"; shift 2 ;;
    --shell-rc)     opt_shell_rc="${2:-}";    shift 2 ;;
    --shell-mode)   opt_shell_mode="${2:-}";  shift 2 ;;
    --shared)       opt_shared="${2:-}";      shift 2 ;;
    --add-shared)   opt_add_shared="${2:-}";  shift 2 ;;
    --remove-shared) opt_remove_shared="${2:-}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

case "$cmd" in
  add)
    [[ -n "$opt_name" ]]        || { echo "--name required" >&2; exit 1; }
    [[ -n "$opt_config_dir" ]]  || { echo "--config-dir required" >&2; exit 1; }
    [[ -n "$opt_shared_pool" ]] || { echo "--shared-pool required" >&2; exit 1; }
    [[ -n "$opt_shell_rc" ]]    || { echo "--shell-rc required" >&2; exit 1; }
    [[ -n "$opt_shell_mode" ]]  || { echo "--shell-mode required" >&2; exit 1; }
    build_add "$opt_name" "$opt_config_dir" "$opt_shared_pool" \
              "$opt_shell_rc" "$opt_shell_mode" "$opt_shared"
    ;;
  edit)
    [[ -n "$opt_name" ]]        || { echo "--name required" >&2; exit 1; }
    [[ -n "$opt_config_dir" ]]  || { echo "--config-dir required" >&2; exit 1; }
    [[ -n "$opt_shared_pool" ]] || { echo "--shared-pool required" >&2; exit 1; }
    build_edit "$opt_name" "$opt_config_dir" "$opt_shared_pool" \
               "$opt_add_shared" "$opt_remove_shared"
    ;;
  unlink)
    [[ -n "$opt_name" ]]        || { echo "--name required" >&2; exit 1; }
    [[ -n "$opt_config_dir" ]]  || { echo "--config-dir required" >&2; exit 1; }
    [[ -n "$opt_shell_rc" ]]    || { echo "--shell-rc required" >&2; exit 1; }
    [[ -n "$opt_shell_mode" ]]  || { echo "--shell-mode required" >&2; exit 1; }
    build_unlink "$opt_name" "$opt_config_dir" "$opt_shell_rc" "$opt_shell_mode"
    ;;
  *)
    echo "Usage: $0 {add|edit|unlink} [--name ...] [--config-dir ...] [--shared-pool ...] [...]" >&2
    exit 1
    ;;
esac
