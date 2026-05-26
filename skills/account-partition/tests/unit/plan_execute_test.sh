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

# 시나리오 3: archive_dir — dir 생성 → archive → 원본 사라짐
sb3=$(make_sandbox)
trap 'cleanup_sandbox "$sb"; cleanup_sandbox "$sb2"; cleanup_sandbox "$sb3"' EXIT

mkdir -p "$sb3/.claude-arch"
echo "data" > "$sb3/.claude-arch/file.txt"

plan_arch=$(cat <<JSON
{
  "metadata": {"action":"unlink","alias_name":"arch","config_dir":"$sb3/.claude-arch"},
  "operations": [{"op":"archive_dir","src":"$sb3/.claude-arch","remove_after":true}]
}
JSON
)

echo "$plan_arch" | PLAN_DIR="$sb3" SCRIPTS_DIR="$SCRIPTS" bash "$SCRIPTS/plan-execute.sh"

if [[ -d "$sb3/.claude-arch" ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); ASSERT_FAILURES+=("archive 후 원본 잔존"); echo "  ✗ archive 후 원본 잔존"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ archive 후 원본 제거됨"
fi

shopt -s nullglob
archives=("$sb3/.claude-arch.removed."*.tar.gz)
if [[ ${#archives[@]} -gt 0 ]]; then
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ archive 파일 생성됨"
else
  ASSERT_FAIL=$((ASSERT_FAIL+1)); ASSERT_FAILURES+=("archive 파일 없음"); echo "  ✗ archive 파일 없음"
fi
shopt -u nullglob

print_summary
