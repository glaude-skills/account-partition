#!/usr/bin/env bash
# 외부 alias·계정 발견.
# 사용:
#   discover.sh list-dirs       → 계정 후보 디렉토리 절대경로 한 줄씩
#   discover.sh list-ignored    → 무시된 후보 디렉토리 한 줄씩
#   discover.sh meta <dir>      → 단일 디렉토리의 메타데이터 (alias, email) JSON
#
# 환경변수:
#   HOME         (기본: $HOME)
#   SHARED_POOL  (기본: $HOME/.claude-shared)

set -uo pipefail

HOME="${HOME:?HOME is required}"
SHARED_POOL="${SHARED_POOL:-$HOME/.claude-shared}"

# SHARED_POOL 정규화 (symlink·상대경로 처리)
_SP_DIR=$(dirname "$SHARED_POOL")
_SP_BASE=$(basename "$SHARED_POOL")
if [[ -d "$_SP_DIR" ]]; then
  SHARED_POOL_NORM="$(cd "$_SP_DIR" && pwd)/$_SP_BASE"
else
  SHARED_POOL_NORM="$SHARED_POOL"
fi

is_account_candidate() {
  local dir="$1"
  # default ~/.claude is always a candidate if it's a directory (design §13)
  if [[ "$dir" == "$HOME/.claude" ]]; then
    return 0
  fi
  [[ -f "$dir/.claude.json" ]] && return 0
  return 1
}

list_dirs() (
  shopt -s nullglob dotglob 2>/dev/null
  for entry in "$HOME"/.claude "$HOME"/.claude-*; do
    [[ -d "$entry" ]] || continue
    [[ "$entry" == "$SHARED_POOL" || "$entry" == "$SHARED_POOL_NORM" ]] && continue
    [[ "$entry" == *.tar.gz ]] && continue
    [[ "$entry" == *.bak.* ]] && continue
    [[ "$entry" == *.removed.* ]] && continue
    [[ "$(basename "$entry")" == ".account-partition-quarantine" ]] && continue
    if is_account_candidate "$entry"; then
      echo "$entry"
    fi
  done
)

list_ignored() (
  shopt -s nullglob dotglob 2>/dev/null
  for entry in "$HOME"/.claude-*; do
    [[ -d "$entry" ]] || continue
    [[ "$entry" == "$SHARED_POOL" || "$entry" == "$SHARED_POOL_NORM" ]] && continue
    [[ "$entry" == *.bak.* ]] && continue
    [[ "$entry" == *.removed.* ]] && continue
    if ! is_account_candidate "$entry"; then
      echo "$entry"
    fi
  done
)

meta_for_dir() {
  local dir="$1"
  local email=""

  if [[ -f "$dir/.claude.json" ]]; then
    email=$(CLAUDE_JSON_PATH="$dir/.claude.json" python3 -c "
import json, os, sys
try:
    with open(os.environ['CLAUDE_JSON_PATH']) as f:
        d = json.load(f)
    print(d.get('oauthAccount', {}).get('emailAddress', ''))
except Exception:
    pass
" 2>/dev/null)
  fi

  local name
  name=$(basename "$dir")
  if [[ "$name" == ".claude" ]]; then
    name="claude (기본)"
  else
    name="${name#.}"
  fi

  AP_DIR="$dir" AP_ALIAS="$name" AP_EMAIL="$email" python3 -c "
import json, os
print(json.dumps({
  'dir':   os.environ['AP_DIR'],
  'alias': os.environ['AP_ALIAS'],
  'email': os.environ['AP_EMAIL'],
}))
"
}

cmd="${1:-help}"
case "$cmd" in
  list-dirs)    list_dirs ;;
  list-ignored) list_ignored ;;
  meta)         meta_for_dir "${2:?Usage: $0 meta <dir>}" ;;
  *)
    echo "Usage: $0 {list-dirs|list-ignored|meta <dir>}" >&2
    exit 1
    ;;
esac
