#!/usr/bin/env bash
# 안전장치 유틸: 활성 세션 감지, lockfile, 백업, 격리 보존.
# 사용:
#   safety.sh lock <config_dir> <pid>              → lockfile 획득 (다른 살아있는 PID 점유 시 실패)
#   safety.sh unlock <config_dir> <pid>            → lockfile 해제 (같은 PID여야 함)
#   safety.sh check-active <config_dir>            → 해당 CONFIG_DIR을 점유한 claude 프로세스 있는지 (exit 0=있음, 1=없음)
#   safety.sh backup <path>                        → <path>.bak.<ts> 생성 후 백업 경로 출력 (권한 0600)
#   safety.sh quarantine <config_dir> <item_path>  → <config_dir>/.account-partition-quarantine/<name>.<ts> 으로 이동, 경로 출력

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/platform.sh"

now_ts() {
  date +%Y%m%d-%H%M%S
}

unique_ts() {
  # 같은 초 내 연속 호출에서도 유일성 보장 (PID suffix)
  echo "$(now_ts)-$$"
}

lock_path() {
  echo "$1/.account-partition.lock"
}

acquire_lock() {
  local config_dir="$1"
  local pid="$2"
  local lock
  lock=$(lock_path "$config_dir")

  if [[ -f "$lock" ]]; then
    local existing
    existing=$(cat "$lock" 2>/dev/null || echo "")
    if [[ "$existing" == "$pid" ]]; then
      return 0  # idempotent
    fi
    if [[ -n "$existing" ]] && kill -0 "$existing" 2>/dev/null; then
      echo "Error: lock held by PID $existing" >&2
      return 1
    fi
    rm -f "$lock"   # 좀비 lock 정리
  fi

  mkdir -p "$config_dir"
  # noclobber로 원자적 create. 좀비 정리와 write 사이 race window는 남으나
  # 단일 머신·단일 사용자 가정에서 실용적 위험 낮음. v2 후속에서 flock/mkdir 기반 강화.
  if ( set -C; echo "$pid" > "$lock" ) 2>/dev/null; then
    return 0
  fi
  echo "Error: lock race detected (another process acquired between cleanup and write)" >&2
  return 1
}

release_lock() {
  local config_dir="${1:?Usage: $0 unlock <config_dir> <pid>}"
  local pid="${2:?pid required}"
  local lock
  lock=$(lock_path "$config_dir")

  # lockfile 없으면 무음 성공 (이미 해제됨 또는 한번도 잡힌 적 없음 — 호출자 안심).
  if [[ -f "$lock" ]]; then
    local existing
    existing=$(cat "$lock")
    if [[ "$existing" == "$pid" ]]; then
      rm -f "$lock"
    else
      echo "Error: lock held by $existing, not $pid" >&2
      return 1
    fi
  fi
}

check_active_processes() {
  local config_dir="${1:?Usage: $0 check-active <config_dir>}"

  # daemon 마커 확인 — daemon.lock 의 pid 와 daemon.status.json 의 supervisorPid (구버전: pid) 모두 본다
  if [[ -f "$config_dir/daemon.lock" || -f "$config_dir/daemon.status.json" ]]; then
    local daemon_pid
    daemon_pid=$(CFG="$config_dir" python3 -c "
import json, os, sys
sys.path.insert(0, os.path.dirname(os.environ['AP_LIB']))
from aplib import npath
cfg = npath(os.environ['CFG'])
for fn, keys in (('daemon.lock', ('pid',)), ('daemon.status.json', ('supervisorPid', 'pid'))):
    try:
        with open(os.path.join(cfg, fn), encoding='utf-8') as f:
            d = json.load(f)
    except Exception:
        continue
    for k in keys:
        if d.get(k):
            print(d[k]); raise SystemExit
" 2>/dev/null)
    if [[ -n "$daemon_pid" ]] && ap_pid_alive "$daemon_pid"; then
      echo "Active daemon: PID $daemon_pid (config: $config_dir)"
      return 0
    fi
  fi

  # claude 프로세스 환경변수 매칭 (best-effort). Windows 는 다른 프로세스 env 를 읽을 수 없어 daemon 마커만 본다.
  case "$(ap_os)" in
    linux)
      local envf
      for envf in /proc/[0-9]*/environ; do
        local pid="${envf#/proc/}"; pid="${pid%/environ}"
        grep -q claude "/proc/$pid/cmdline" 2>/dev/null || continue
        if tr '\0' '\n' < "$envf" 2>/dev/null | grep -qxF "CLAUDE_CONFIG_DIR=$config_dir"; then
          echo "Active claude process: PID $pid (config: $config_dir)"
          return 0
        fi
      done
      ;;
    macos)
      while IFS= read -r pid; do
        local env_dir
        env_dir=$(ps eww -p "$pid" 2>/dev/null | grep -oE "CLAUDE_CONFIG_DIR=[^ ]+" | head -1 | cut -d= -f2)
        if [[ "$env_dir" == "$config_dir" ]]; then
          echo "Active claude process: PID $pid (config: $config_dir)"
          return 0
        fi
      done < <(pgrep -f 'claude' 2>/dev/null || true)
      ;;
  esac

  return 1
}

backup_file() {
  local path="$1"
  [[ -e "$path" ]] || { echo "Error: $path not found" >&2; return 1; }
  local ts; ts=$(unique_ts)
  local backup="${path}.bak.${ts}"
  cp -p "$path" "$backup" || { echo "Error: backup failed (cp)" >&2; return 1; }
  if [[ "$(ap_os)" != windows ]]; then
    chmod 0600 "$backup" || { echo "Error: chmod failed on $backup" >&2; rm -f "$backup"; return 1; }
  fi
  echo "$backup"
}

quarantine_item() {
  local config_dir="${1:?Usage: $0 quarantine <config_dir> <item_path>}"
  local item_path="${2:?item_path required}"
  [[ -e "$item_path" ]] || { echo "Error: $item_path not found" >&2; return 1; }
  local ts; ts=$(unique_ts)
  local q_dir="$config_dir/.account-partition-quarantine"
  mkdir -p "$q_dir"

  local item_name
  item_name=$(basename "$item_path")
  local dest="$q_dir/${item_name}.${ts}"

  mv "$item_path" "$dest" || { echo "Error: quarantine move failed" >&2; return 1; }
  echo "$dest"
}

cmd="${1:-help}"
case "$cmd" in
  lock)         acquire_lock "${2:-}" "${3:-}" ;;
  unlock)       release_lock "${2:-}" "${3:-}" ;;
  check-active) check_active_processes "${2:-}" ;;
  backup)       backup_file "${2:-}" ;;
  quarantine)   quarantine_item "${2:-}" "${3:-}" ;;
  *)
    echo "Usage: $0 {lock|unlock|check-active|backup|quarantine} ..." >&2
    exit 1
    ;;
esac
