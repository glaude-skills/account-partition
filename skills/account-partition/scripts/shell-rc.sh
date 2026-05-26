#!/usr/bin/env bash
# zshrc alias 라인 자동 편집·발견.
# 사용:
#   shell-rc.sh add <rc> <name> <config_dir>     → 주석 블록 + alias 추가/교체 (idempotent)
#   shell-rc.sh remove <rc> <name>               → 스킬 관리 블록만 제거
#   shell-rc.sh list <rc>                        → 발견된 alias 한 줄씩: "name:source" (managed|external)
#   shell-rc.sh render <name> <config_dir>       → alias 라인만 출력 (수동 안내용)
#
# 자동 편집은 '# account-partition: <name>' 주석 블록만 대상.
# 외부 alias는 list로 발견까지만, 수정 안 함.

set -uo pipefail

MARKER_PREFIX="# account-partition:"

render_alias_line() {
  local name="$1"
  local config_dir="$2"
  echo "alias claude-${name}=\"CLAUDE_CONFIG_DIR=${config_dir} command claude\""
}

render_block() {
  local name="$1"
  local config_dir="$2"
  echo "${MARKER_PREFIX} ${name}"
  render_alias_line "$name" "$config_dir"
}

add_alias() {
  local rc="$1"
  local name="$2"
  local config_dir="$3"

  remove_alias "$rc" "$name"

  # 파일 끝 개행 보장
  if [[ -s "$rc" ]] && [[ -n "$(tail -c 1 "$rc")" ]]; then
    printf '\n' >> "$rc"
  fi
  render_block "$name" "$config_dir" >> "$rc"
}

remove_alias() {
  local rc="$1"
  local name="$2"
  [[ -f "$rc" ]] || return 0

  RC_PATH="$rc" REMOVE_NAME="$name" python3 -c "
import os, re, sys
rc = os.environ['RC_PATH']
name = os.environ['REMOVE_NAME']
marker_re = re.compile(r'^# account-partition:\s*' + re.escape(name) + r'\s*$')

with open(rc) as f:
    lines = f.readlines()

new_lines = []
skip_next = False
for line in lines:
    if skip_next:
        skip_next = False
        continue
    if marker_re.match(line):
        skip_next = True
        continue
    new_lines.append(line)

with open(rc, 'w') as f:
    f.writelines(new_lines)
"
}

list_aliases() {
  local rc="$1"
  [[ -f "$rc" ]] || return 0

  RC_PATH="$rc" python3 -c "
import os, re
rc = os.environ['RC_PATH']
managed_re = re.compile(r'^# account-partition:\s*(\S+)\s*$')
alias_re = re.compile(r'^\s*alias\s+claude-([A-Za-z0-9_-]+)\s*=')

with open(rc) as f:
    lines = f.readlines()

managed = set()
external = set()
i = 0
while i < len(lines):
    m = managed_re.match(lines[i])
    if m and i + 1 < len(lines):
        am = alias_re.match(lines[i+1])
        if am and am.group(1) == m.group(1):
            managed.add(m.group(1))
            i += 2
            continue
    a = alias_re.match(lines[i])
    if a:
        external.add(a.group(1))
    i += 1

for n in sorted(managed):
    print(f'{n}:managed')
for n in sorted(external - managed):
    print(f'{n}:external')
"
}

cmd="${1:-help}"
case "$cmd" in
  add)    add_alias "${2:?Usage: $0 add <rc> <name> <config_dir>}" "${3:?name required}" "${4:?config_dir required}" ;;
  remove) remove_alias "${2:?Usage: $0 remove <rc> <name>}" "${3:?name required}" ;;
  list)   list_aliases "${2:?Usage: $0 list <rc>}" ;;
  render) render_alias_line "${2:?Usage: $0 render <name> <config_dir>}" "${3:?config_dir required}" ;;
  *)
    echo "Usage: $0 {add|remove|list|render} ..." >&2
    exit 1
    ;;
esac
