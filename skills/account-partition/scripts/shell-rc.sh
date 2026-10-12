#!/usr/bin/env bash
# 셸 설정 파일의 관리 블록 편집·발견 (단일 파일 단위, 저수준).
# 여러 셸에 동시 기록하는 고수준 흐름은 ap.sh plan-add / plan-adopt / plan-unlink 를 쓴다.
# 사용:
#   shell-rc.sh add <rc> <name> <config_dir> [<kind>]  → 관리 블록 추가/교체 (idempotent). kind: posix(기본)|powershell
#   shell-rc.sh remove <rc> <name>                     → 관리 블록만 제거 (v0.4 형식 포함)
#   shell-rc.sh list <rc> [<kind>]                     → "name:managed" / "name:external" 한 줄씩
#   shell-rc.sh render <name> <config_dir> [<kind>]    → 블록 텍스트만 출력 (수동 안내용)
#
# 자동 편집은 '# >>> account-partition: <name> >>>' 블록(및 v0.4 '# account-partition: <name>' + alias)만 대상.
# 외부 정의는 list 로 발견까지만, 수정은 adopt 흐름에서만.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/platform.sh"

_acct_json() {
  CFG="$1" python3 -c "
import json, os, sys
sys.path.insert(0, os.path.dirname(os.environ['AP_LIB']))
import aplib
print(json.dumps({'mode': 'standard', 'config_dir': aplib.to_home_rel(os.environ['CFG']), 'token_dir': None}))
"
}

cmd="${1:-help}"
case "$cmd" in
  add)
    rc="${2:?Usage: $0 add <rc> <name> <config_dir> [kind]}"; name="${3:?name required}"; cfg="${4:?config_dir required}"
    python3 "$AP_LIB" block-write "$rc" "$name" "${5:-posix}" "$(_acct_json "$cfg")"
    ;;
  remove)
    python3 "$AP_LIB" block-remove "${2:?Usage: $0 remove <rc> <name>}" "${3:?name required}" >/dev/null
    ;;
  list)
    rc="${2:?Usage: $0 list <rc> [kind]}"; kind="${3:-posix}"
    RC="$rc" KIND="$kind" python3 -c "
import os, sys
sys.path.insert(0, os.path.dirname(os.environ['AP_LIB']))
import aplib
managed = set(aplib.list_blocks(os.environ['RC']))
ext = {e['name'] for e in aplib.parse_rc_externals(os.environ['RC'], os.environ['KIND'])}
for n in sorted(managed):
    print(f'{n}:managed')
for n in sorted(ext - managed):
    print(f'{n}:external')
"
    ;;
  render)
    name="${2:?Usage: $0 render <name> <config_dir> [kind]}"; cfg="${3:?config_dir required}"
    NAME="$name" KIND="${4:-posix}" ACCT="$(_acct_json "$cfg")" python3 -c "
import json, os, sys
sys.path.insert(0, os.path.dirname(os.environ['AP_LIB']))
import aplib
print('\n'.join(aplib.render(os.environ['KIND'], os.environ['NAME'], json.loads(os.environ['ACCT']))))
"
    ;;
  *)
    echo "Usage: $0 {add|remove|list|render} ..." >&2
    exit 1
    ;;
esac
