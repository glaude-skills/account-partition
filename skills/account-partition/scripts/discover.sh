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

is_account_candidate() {
  local dir="$1"
  [[ -f "$dir/.claude.json" ]] && return 0
  return 1
}

list_dirs() {
  local exclude_pool
  exclude_pool=$(cd "$(dirname "$SHARED_POOL")" 2>/dev/null && pwd)/$(basename "$SHARED_POOL")

  shopt -s nullglob dotglob 2>/dev/null
  for entry in "$HOME"/.claude "$HOME"/.claude-*; do
    [[ -d "$entry" ]] || continue
    [[ "$entry" == "$SHARED_POOL" ]] && continue
    [[ "$entry" == "$exclude_pool" ]] && continue
    [[ "$entry" == *.tar.gz ]] && continue
    [[ "$entry" == *.bak.* ]] && continue
    [[ "$entry" == *.removed.* ]] && continue
    [[ "$(basename "$entry")" == ".account-partition-quarantine" ]] && continue
    if is_account_candidate "$entry"; then
      echo "$entry"
    fi
  done
}

list_ignored() {
  shopt -s nullglob dotglob 2>/dev/null
  for entry in "$HOME"/.claude-*; do
    [[ -d "$entry" ]] || continue
    [[ "$entry" == "$SHARED_POOL" ]] && continue
    [[ "$entry" == *.bak.* ]] && continue
    [[ "$entry" == *.removed.* ]] && continue
    if ! is_account_candidate "$entry"; then
      echo "$entry"
    fi
  done
}

meta_for_dir() {
  local dir="$1"
  local email=""

  if [[ -f "$dir/.claude.json" ]]; then
    email=$(python3 -c "
import json
try:
    d = json.load(open('$dir/.claude.json'))
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

  python3 -c "
import json
print(json.dumps({
  'dir': '$dir',
  'alias': '$name',
  'email': '$email',
}))
"
}

cmd="${1:-help}"
case "$cmd" in
  list-dirs)    list_dirs ;;
  list-ignored) list_ignored ;;
  meta)         meta_for_dir "$2" ;;
  *)
    echo "Usage: $0 {list-dirs|list-ignored|meta <dir>}" >&2
    exit 1
    ;;
esac
