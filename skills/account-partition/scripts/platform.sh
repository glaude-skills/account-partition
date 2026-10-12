#!/usr/bin/env bash
# 플랫폼 공통 설정. 모든 bash 헬퍼가 source 한다.
#   - Python UTF-8 강제 (Windows cp949 콘솔에서 한글·기호 출력 시 죽는 문제)
#   - python3 를 실제 동작하는 인터프리터로 위임 (Windows Store stub 제외)
#   - AP_LIB: aplib.py 경로
#   - ap_os: macos|linux|windows (AP_OS_OVERRIDE 우선)

export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8

AP_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AP_LIB="$AP_SCRIPTS_DIR/aplib.py"

_ap_resolve_python() {
  local cand
  for cand in python3 python py; do
    local p
    p=$(type -P "$cand" 2>/dev/null) || continue
    [[ -n "$p" ]] || continue
    # Windows Store 의 가짜 python3 stub 은 버전 출력에 실패한다
    if "$p" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

if [[ -z "${AP_PYTHON:-}" ]]; then
  AP_PYTHON=$(_ap_resolve_python) || {
    echo "account-partition: python 3.8+ 을 찾을 수 없습니다. python3 를 설치한 뒤 다시 실행하세요." >&2
    AP_PYTHON=python3
  }
  export AP_PYTHON
fi

python3() { "$AP_PYTHON" "$@"; }

# Python 에서 bash 를 부를 때 쓸 경로. Windows 에서 그냥 "bash" 는 System32 의 WSL bash 로 풀린다.
if [[ -z "${AP_BASH:-}" ]]; then
  if command -v cygpath >/dev/null 2>&1; then
    AP_BASH=$(cygpath -w "$BASH")
  else
    AP_BASH="$BASH"
  fi
  export AP_BASH
fi

ap_os() {
  if [[ -n "${AP_OS_OVERRIDE:-}" ]]; then echo "$AP_OS_OVERRIDE"; return; fi
  case "$(uname -s 2>/dev/null)" in
    Darwin) echo macos ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo linux ;;
  esac
}

ap_pid_alive() {
  local pid="$1"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null && return 0
  # Windows: claude 데몬 PID 는 MSYS PID 가 아니라 Windows PID
  if [[ "$(uname -s 2>/dev/null)" == MINGW* || "$(uname -s 2>/dev/null)" == MSYS* ]]; then
    tasklist //FI "PID eq $pid" //NH //FO CSV 2>/dev/null | grep -q "\"$pid\""
    return
  fi
  return 1
}
