#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

sb=$(make_sandbox)
trap 'cleanup_sandbox "$sb"' EXIT

# 시나리오: create_dir + create_symlink 2개 완료 후 다음 op에서 실패한 상태
mkdir -p "$sb/.claude-test"
mkdir -p "$sb/shared"
echo "content" > "$sb/shared/settings.json"
ln -s "$sb/shared/settings.json" "$sb/.claude-test/settings.json"

# 상태 파일: 2개 op 완료, 3번째에서 실패
cat > "$sb/.account-partition-state.json" <<JSON
{
  "metadata": {"action":"add","alias_name":"test","config_dir":"$sb/.claude-test"},
  "operations": [
    {"op":"create_dir","path":"$sb/.claude-test"},
    {"op":"create_symlink","src":"$sb/shared/settings.json","dst":"$sb/.claude-test/settings.json"},
    {"op":"create_symlink","src":"$sb/shared/plugins","dst":"$sb/.claude-test/plugins"}
  ],
  "_completed": [0, 1],
  "_failed_at": 2,
  "_error": "test"
}
JSON

PLAN_DIR="$sb" SCRIPTS_DIR="$SCRIPTS" bash "$SCRIPTS/plan-rollback.sh"

# symlink 제거 검증
if [[ -L "$sb/.claude-test/settings.json" ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); ASSERT_FAILURES+=("symlink 롤백 실패"); echo "  ✗ symlink 롤백 실패"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ symlink 롤백 OK"
fi

# 빈 디렉토리는 제거 (idx 0 = create_dir, 안에 다른 거 없으면 rmdir)
if [[ -d "$sb/.claude-test" ]]; then
  # 이 케이스는 안에 quarantine 등 없으면 빈 상태 → 제거됨
  if [[ -z "$(ls -A "$sb/.claude-test" 2>/dev/null)" ]]; then
    ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 빈 dir 롤백 실패 (rmdir 안 됨)"
  else
    ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ dir 보존 (내용 있음)"
  fi
fi

# 상태 파일 archive로 변경 (보존)
if [[ -f "$sb/.account-partition-state.json" ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); ASSERT_FAILURES+=("상태 파일 잔존"); echo "  ✗ 상태 파일 잔존"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 상태 파일 정리 완료"
fi

# archive 파일 존재
shopt -s nullglob
archives=("$sb"/.account-partition-state.json.rolled-back.*)
if [[ ${#archives[@]} -gt 0 ]]; then
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ archive 파일 생성됨: ${archives[0]##*/}"
else
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ archive 파일 없음"
fi

# 시나리오 2: 상태 파일 없을 때 → exit non-zero + 친화적 에러
sb2=$(make_sandbox)
if PLAN_DIR="$sb2" SCRIPTS_DIR="$SCRIPTS" bash "$SCRIPTS/plan-rollback.sh" 2>/dev/null; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 상태 파일 없는데 exit=0"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 상태 파일 없을 때 exit=non-zero"
fi
cleanup_sandbox "$sb2"

# 시나리오 3: append_block 롤백 — marker 블록 제거 확인
sb3=$(make_sandbox)
echo -e "existing line\n# account-partition: roll\nalias claude-roll=\"x\"\n" > "$sb3/.zshrc"
cat > "$sb3/.account-partition-state.json" <<JSON
{
  "metadata": {"action":"add","alias_name":"roll","config_dir":"$sb3/.claude-roll"},
  "operations": [
    {"op":"append_block","file":"$sb3/.zshrc","marker":"# account-partition: roll","lines":["alias claude-roll=\"x\""]}
  ],
  "_completed": [0],
  "_failed_at": 1,
  "_error": "test"
}
JSON

PLAN_DIR="$sb3" SCRIPTS_DIR="$SCRIPTS" bash "$SCRIPTS/plan-rollback.sh"

after=$(cat "$sb3/.zshrc")
if [[ "$after" == *"# account-partition: roll"* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ marker 블록 롤백 실패"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ marker 블록 롤백 OK"
fi
assert_contains "$after" "existing line" "기존 라인 보존"
cleanup_sandbox "$sb3"

print_summary
