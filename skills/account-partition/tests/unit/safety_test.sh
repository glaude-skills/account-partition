#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

sb=$(make_sandbox)
trap 'cleanup_sandbox "$sb"' EXIT

# lockfile 획득
mkdir -p "$sb/.claude-test"
if bash "$SCRIPTS/safety.sh" lock "$sb/.claude-test" "$$"; then
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ lock 획득 성공"
else
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ lock 획득 실패"
fi

assert_file_exists "$sb/.claude-test/.account-partition.lock"

# 두 번째 lock (다른 살아있는 PID 시뮬레이션 어려움 — 자기 PID는 idempotent해야)
if bash "$SCRIPTS/safety.sh" lock "$sb/.claude-test" "$$"; then
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 같은 PID 재진입 OK (idempotent)"
else
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 같은 PID 재진입 거부됨"
fi

# 좀비 lock — 존재하지 않는 PID로 lock 파일 쓰면 정리되어야
rm -f "$sb/.claude-test/.account-partition.lock"
echo "999999" > "$sb/.claude-test/.account-partition.lock"
if bash "$SCRIPTS/safety.sh" lock "$sb/.claude-test" "$$"; then
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 좀비 lock 정리 후 획득 OK"
else
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 좀비 lock 정리 실패"
fi

# unlock
bash "$SCRIPTS/safety.sh" unlock "$sb/.claude-test" "$$"
if [[ -f "$sb/.claude-test/.account-partition.lock" ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ unlock 후에도 lockfile 잔존"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ unlock 완료"
fi

# 백업 유틸
echo "test content" > "$sb/file.txt"
backup_path=$(bash "$SCRIPTS/safety.sh" backup "$sb/file.txt")
assert_file_exists "$backup_path"
assert_contains "$backup_path" ".bak." "백업 파일 이름에 .bak. 포함"
assert_eq "$(cat "$backup_path")" "test content" "백업 내용 보존"

# 백업 권한 0600
perm=$(stat -f '%Lp' "$backup_path" 2>/dev/null || stat -c '%a' "$backup_path" 2>/dev/null)
assert_eq "$perm" "600" "백업 파일 권한 0600"

# 격리 보존
mkdir -p "$sb/.claude-test"
echo "old content" > "$sb/.claude-test/settings.json"
q_path=$(bash "$SCRIPTS/safety.sh" quarantine "$sb/.claude-test" "$sb/.claude-test/settings.json")
assert_file_exists "$q_path"
assert_contains "$q_path" ".account-partition-quarantine" "격리 디렉토리 안에"
assert_contains "$q_path" "settings.json" "원래 파일 이름 유지"
# 원래 위치는 없어야
if [[ -e "$sb/.claude-test/settings.json" ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 원래 위치에 파일 잔존"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 원래 위치에서 이동됨"
fi

# check-active — 현재 살아있는 PID로 daemon 시뮬레이션
mkdir -p "$sb/.claude-active"
touch "$sb/.claude-active/daemon.lock"
echo "{\"pid\":$$}" > "$sb/.claude-active/daemon.status.json"
if bash "$SCRIPTS/safety.sh" check-active "$sb/.claude-active"; then
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ check-active: 활성 daemon 감지"
else
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ check-active: 활성 daemon 감지 실패"
fi

# check-active — 마커 없는 dir은 inactive
mkdir -p "$sb/.claude-quiet"
if bash "$SCRIPTS/safety.sh" check-active "$sb/.claude-quiet"; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ check-active false-positive (마커 없는 dir)"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ check-active: 비활성 dir 정확 판별"
fi

print_summary
