#!/usr/bin/env bash
# 공통 assertion 함수. 각 *_test.sh에서 source.

if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  NC=''
fi

ASSERT_PASS=0
ASSERT_FAIL=0
ASSERT_FAILURES=()

assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="${3:-}"

  if [[ "$actual" == "$expected" ]]; then
    ASSERT_PASS=$((ASSERT_PASS + 1))
    echo -e "  ${GREEN}✓${NC} ${msg:-assertion passed}"
  else
    ASSERT_FAIL=$((ASSERT_FAIL + 1))
    local detail="${msg:-assertion failed}\n    expected: $expected\n    actual:   $actual"
    ASSERT_FAILURES+=("$detail")
    echo -e "  ${RED}✗${NC} $detail"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-}"

  if [[ "$haystack" == *"$needle"* ]]; then
    ASSERT_PASS=$((ASSERT_PASS + 1))
    echo -e "  ${GREEN}✓${NC} ${msg:-contains '$needle'}"
  else
    ASSERT_FAIL=$((ASSERT_FAIL + 1))
    local detail="${msg:-does not contain '$needle'}\n    haystack: $haystack"
    ASSERT_FAILURES+=("$detail")
    echo -e "  ${RED}✗${NC} $detail"
  fi
}

assert_file_exists() {
  local path="$1"
  local msg="${2:-file exists: $path}"

  if [[ -e "$path" ]]; then
    ASSERT_PASS=$((ASSERT_PASS + 1))
    echo -e "  ${GREEN}✓${NC} $msg"
  else
    ASSERT_FAIL=$((ASSERT_FAIL + 1))
    ASSERT_FAILURES+=("$msg")
    echo -e "  ${RED}✗${NC} $msg"
  fi
}

assert_symlink_target() {
  local link="$1"
  local expected_target="$2"
  local msg="${3:-symlink $link -> $expected_target}"

  if [[ -L "$link" ]]; then
    local actual_target
    actual_target=$(readlink "$link")
    if [[ "$actual_target" == "$expected_target" ]]; then
      ASSERT_PASS=$((ASSERT_PASS + 1))
      echo -e "  ${GREEN}✓${NC} $msg"
      return
    fi
  fi
  ASSERT_FAIL=$((ASSERT_FAIL + 1))
  ASSERT_FAILURES+=("$msg")
  echo -e "  ${RED}✗${NC} $msg"
}

print_summary() {
  local total=$((ASSERT_PASS + ASSERT_FAIL))
  echo ""
  echo "  Tests: $total  Pass: $ASSERT_PASS  Fail: $ASSERT_FAIL"
  if [[ $ASSERT_FAIL -gt 0 ]]; then
    return 1
  fi
}

make_sandbox() {
  local sb
  sb=$(mktemp -d -t account-partition-test.XXXXXX)
  echo "$sb"
}

cleanup_sandbox() {
  local sb="$1"
  [[ -d "$sb" ]] && rm -rf "$sb"
}

# ── 멀티 OS 헬퍼 (v0.5) ──
is_windows() {
  case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac
}

# 스크립트가 셸 블록에 기록하는 형태의 경로 (Windows 는 백슬래시 네이티브 경로)
native_path() {
  if is_windows; then
    # 홈 아래 경로는 셸 블록에 "$USERPROFILE\..." 형태로 기록된다 — 홈 이후 부분만 비교
    local w up
    w=$(cygpath -w "$1"); up=$(cygpath -w "$USERPROFILE")
    if [[ "${w,,}" == "${up,,}\\"* ]]; then echo "${w:${#up}}"; else echo "$w"; fi
  else
    echo "$1"
  fi
}

# 두 경로가 같은 실체를 가리키는지 (symlink, junction, Windows 하드링크 대체 포함)
assert_same_file() {
  local a="$1" b="$2" msg="${3:-same file: $1 == $2}"
  if [[ "$a" -ef "$b" ]]; then
    ASSERT_PASS=$((ASSERT_PASS + 1)); echo -e "  ${GREEN}✓${NC} $msg"
  else
    ASSERT_FAIL=$((ASSERT_FAIL + 1)); ASSERT_FAILURES+=("$msg"); echo -e "  ${RED}✗${NC} $msg"
  fi
}
