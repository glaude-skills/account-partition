#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

sb=$(make_sandbox)
trap 'cleanup_sandbox "$sb"' EXIT

mkdir -p "$sb/shared"
echo "shared-content" > "$sb/shared/settings.json"

# 시나리오 1: create_dir + create_symlink + append_block 성공
plan=$(cat <<JSON
{
  "metadata": {"action":"add","alias_name":"test","config_dir":"$sb/.claude-test"},
  "operations": [
    {"op":"create_dir","path":"$sb/.claude-test","mode":"0700"},
    {"op":"create_symlink","src":"$sb/shared/settings.json","dst":"$sb/.claude-test/settings.json"},
    {"op":"append_block","file":"$sb/.zshrc","marker":"# account-partition: test","lines":["alias claude-test=\"x\""],"backup":false}
  ]
}
JSON
)
touch "$sb/.zshrc"

# 실행
echo "$plan" | PLAN_DIR="$sb" SCRIPTS_DIR="$SCRIPTS" bash "$SCRIPTS/plan-execute.sh"

# 결과 검증
assert_file_exists "$sb/.claude-test"
assert_symlink_target "$sb/.claude-test/settings.json" "$sb/shared/settings.json"

content=$(cat "$sb/.zshrc")
assert_contains "$content" "# account-partition: test" "marker 추가"
assert_contains "$content" "alias claude-test" "alias 추가"

# 성공 시 상태 파일 삭제됨
if [[ -f "$sb/.account-partition-state.json" ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); ASSERT_FAILURES+=("성공 후 상태 파일 잔존"); echo "  ✗ 성공 후 상태 파일 잔존"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 성공 후 상태 파일 정리됨"
fi

# 시나리오 2: 중간 실패 시 상태 파일 보존 + exit non-zero
# 두 번째 op에서 실패 유도 (이미 dst 존재 + symlink 아님 + backup 안 함)
sb2=$(make_sandbox)
trap 'cleanup_sandbox "$sb"; cleanup_sandbox "$sb2"' EXIT
mkdir -p "$sb2/.claude-fail"
echo "existing" > "$sb2/.claude-fail/conflict"

plan_fail=$(cat <<JSON
{
  "metadata": {"action":"add","alias_name":"fail","config_dir":"$sb2/.claude-fail"},
  "operations": [
    {"op":"create_dir","path":"$sb2/.claude-fail","mode":"0700"},
    {"op":"create_symlink","src":"/nonexistent-source","dst":"$sb2/.claude-fail/conflict"}
  ]
}
JSON
)

if echo "$plan_fail" | PLAN_DIR="$sb2" SCRIPTS_DIR="$SCRIPTS" bash "$SCRIPTS/plan-execute.sh" 2>/dev/null; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 실패 시나리오인데 exit=0"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 실패 시 exit=non-zero"
fi

# 상태 파일 보존
if [[ -f "$sb2/.account-partition-state.json" ]]; then
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 실패 후 상태 파일 보존"
  # 상태 파일 안에 _completed, _failed_at 필드
  content_state=$(cat "$sb2/.account-partition-state.json")
  assert_contains "$content_state" "_completed" "상태 파일에 _completed 필드"
  assert_contains "$content_state" "_failed_at" "상태 파일에 _failed_at 필드"
else
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 실패 후 상태 파일 없음"
fi

# 시나리오 3: archive_dir만 → 원본 유지 + archive 파일 생성
sb3=$(make_sandbox)
trap 'cleanup_sandbox "$sb"; cleanup_sandbox "$sb2"; cleanup_sandbox "$sb3"' EXIT

mkdir -p "$sb3/.claude-arch"
echo "data" > "$sb3/.claude-arch/file.txt"

plan_arch=$(cat <<JSON
{
  "metadata": {"action":"unlink","alias_name":"arch","config_dir":"$sb3/.claude-arch"},
  "operations": [{"op":"archive_dir","src":"$sb3/.claude-arch"}]
}
JSON
)

echo "$plan_arch" | PLAN_DIR="$sb3" SCRIPTS_DIR="$SCRIPTS" bash "$SCRIPTS/plan-execute.sh"

if [[ -d "$sb3/.claude-arch" ]]; then
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ archive_dir만 → 원본 유지"
else
  ASSERT_FAIL=$((ASSERT_FAIL+1)); ASSERT_FAILURES+=("archive_dir만인데 원본 제거됨"); echo "  ✗ archive_dir만인데 원본 제거됨"
fi

shopt -s nullglob
archives=("$sb3/.claude-arch.removed."*.tar.gz)
if [[ ${#archives[@]} -gt 0 ]]; then
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ archive 파일 생성됨"
else
  ASSERT_FAIL=$((ASSERT_FAIL+1)); ASSERT_FAILURES+=("archive 파일 없음"); echo "  ✗ archive 파일 없음"
fi
shopt -u nullglob

# 시나리오 4: archive_dir + remove_dir → 원본 제거
sb4=$(make_sandbox)
trap 'cleanup_sandbox "$sb"; cleanup_sandbox "$sb2"; cleanup_sandbox "$sb3"; cleanup_sandbox "$sb4"' EXIT

mkdir -p "$sb4/.claude-arch2"
echo "data2" > "$sb4/.claude-arch2/file.txt"

plan_arch2=$(cat <<JSON
{
  "metadata": {"action":"unlink","alias_name":"arch2","config_dir":"$sb4/.claude-arch2"},
  "operations": [
    {"op":"archive_dir","src":"$sb4/.claude-arch2"},
    {"op":"remove_dir","path":"$sb4/.claude-arch2"}
  ]
}
JSON
)

echo "$plan_arch2" | PLAN_DIR="$sb4" SCRIPTS_DIR="$SCRIPTS" bash "$SCRIPTS/plan-execute.sh"

if [[ -d "$sb4/.claude-arch2" ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); ASSERT_FAILURES+=("archive_dir+remove_dir 후 원본 잔존"); echo "  ✗ archive_dir+remove_dir 후 원본 잔존"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ archive_dir+remove_dir → 원본 제거됨"
fi

shopt -s nullglob
archives4=("$sb4/.claude-arch2.removed."*.tar.gz)
if [[ ${#archives4[@]} -gt 0 ]]; then
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ archive 파일 생성됨 (remove_dir 동반)"
else
  ASSERT_FAIL=$((ASSERT_FAIL+1)); ASSERT_FAILURES+=("archive_dir+remove_dir: archive 파일 없음"); echo "  ✗ archive 파일 없음"
fi
shopt -u nullglob

# 시나리오 5: create_symlink backup_if_exists → rollback 시 백업 복원
sb5=$(make_sandbox)
trap 'cleanup_sandbox "$sb"; cleanup_sandbox "$sb2"; cleanup_sandbox "$sb3"; cleanup_sandbox "$sb4"; cleanup_sandbox "$sb5"' EXIT

mkdir -p "$sb5/src"
echo "src-content" > "$sb5/src/item"
echo "original-content" > "$sb5/dst-item"  # rollback 시 복원될 파일

# create_symlink 실행 후 두 번째 op 실패 → 롤백 시 백업 복원 확인
plan_sym=$(cat <<JSON
{
  "metadata": {"action":"add","alias_name":"sym5"},
  "operations": [
    {"op":"create_symlink","src":"$sb5/src/item","dst":"$sb5/dst-item","backup_if_exists":true},
    {"op":"create_symlink","src":"/nonexistent-src","dst":"$sb5/nonexistent-dst"}
  ]
}
JSON
)

if echo "$plan_sym" | PLAN_DIR="$sb5" SCRIPTS_DIR="$SCRIPTS" bash "$SCRIPTS/plan-execute.sh" 2>/dev/null; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 실패 시나리오인데 exit=0"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 두 번째 op 실패 시 exit=non-zero"
fi

# rollback 실행
PLAN_DIR="$sb5" SCRIPTS_DIR="$SCRIPTS" bash "$SCRIPTS/plan-rollback.sh" 2>/dev/null

# 백업이 원래 경로로 복원됐는지 확인
if [[ -f "$sb5/dst-item" ]] && [[ ! -L "$sb5/dst-item" ]]; then
  content5=$(cat "$sb5/dst-item")
  if [[ "$content5" == "original-content" ]]; then
    ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ rollback: symlink 백업 복원됨"
  else
    ASSERT_FAIL=$((ASSERT_FAIL+1)); ASSERT_FAILURES+=("rollback: 내용 불일치"); echo "  ✗ rollback: 내용 불일치 ($content5)"
  fi
else
  ASSERT_FAIL=$((ASSERT_FAIL+1)); ASSERT_FAILURES+=("rollback: 백업 복원 실패"); echo "  ✗ rollback: 백업 복원 실패"
fi

print_summary
