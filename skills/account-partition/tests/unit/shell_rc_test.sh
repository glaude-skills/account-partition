#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

sb=$(make_sandbox)
trap 'cleanup_sandbox "$sb"' EXIT

# 시나리오 1: 빈 zshrc → alias 추가
rc="$sb/.zshrc"
touch "$rc"
bash "$SCRIPTS/shell-rc.sh" add "$rc" "work" "$sb/.claude-work"

content=$(cat "$rc")
assert_contains "$content" "# account-partition: work" "관리 주석 추가"
assert_contains "$content" 'alias claude-work=' "alias 라인 추가"
assert_contains "$content" 'CLAUDE_CONFIG_DIR' "CLAUDE_CONFIG_DIR 포함"
assert_contains "$content" "$sb/.claude-work" "CONFIG_DIR 경로 포함"

# 시나리오 2: 같은 이름 다시 add → idempotent (블록 교체, 라인 수 동일)
old_line_count=$(wc -l < "$rc")
bash "$SCRIPTS/shell-rc.sh" add "$rc" "work" "$sb/.claude-work-NEW"
new_line_count=$(wc -l < "$rc")
assert_eq "$old_line_count" "$new_line_count" "idempotent: 라인 수 동일"
assert_contains "$(cat "$rc")" "$sb/.claude-work-NEW" "교체된 경로 반영"

# 시나리오 3: list — managed alias 출력
out=$(bash "$SCRIPTS/shell-rc.sh" list "$rc")
assert_contains "$out" "work:managed" "list에 work:managed 표시"

# 시나리오 4: 외부 alias (주석 없는 형태) 발견
echo 'alias claude-external="CLAUDE_CONFIG_DIR=/tmp/x command claude"' >> "$rc"
out2=$(bash "$SCRIPTS/shell-rc.sh" list "$rc")
assert_contains "$out2" "external:external" "주석 없는 외부 alias도 list (source=external)"

# 시나리오 5: remove — managed 블록만 제거
bash "$SCRIPTS/shell-rc.sh" remove "$rc" "work"
content_after=$(cat "$rc")
if [[ "$content_after" == *"# account-partition: work"* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL + 1)); ASSERT_FAILURES+=("remove 후에도 marker 잔존"); echo "  ✗ marker 잔존"
else
  ASSERT_PASS=$((ASSERT_PASS + 1)); echo "  ✓ marker 제거됨"
fi
assert_contains "$content_after" "claude-external" "외부 alias는 remove에 영향 받지 않음"

# 시나리오 6: render — alias 라인 단독 출력 (수동 안내용)
rendered=$(bash "$SCRIPTS/shell-rc.sh" render "side" "$sb/.claude-side")
assert_contains "$rendered" 'alias claude-side=' "render에 alias 라인"
assert_contains "$rendered" "$sb/.claude-side" "render에 경로"

print_summary
