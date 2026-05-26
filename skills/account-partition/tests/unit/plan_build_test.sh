#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

# Add: 기본 분리 프리셋 (plugins, skills, commands, agents)
plan=$(bash "$SCRIPTS/plan-build.sh" add \
  --name side \
  --config-dir /Users/test/.claude-side \
  --shared-pool /Users/test/.claude-shared \
  --shell-rc /Users/test/.zshrc \
  --shell-mode auto \
  --shared plugins,skills,commands,agents)

assert_contains "$plan" '"action": "add"' "action=add"
assert_contains "$plan" "side" "alias 이름"
assert_contains "$plan" "create_dir" "create_dir op 존재"
assert_contains "$plan" "/Users/test/.claude-shared/plugins" "plugins symlink src"
assert_contains "$plan" "/Users/test/.claude-side/plugins" "plugins symlink dst"
assert_contains "$plan" "append_block" "append_block op (셸 통합 auto)"
assert_contains "$plan" 'CLAUDE_CONFIG_DIR' "alias 라인에 CLAUDE_CONFIG_DIR"

# settings.json 절대 포함 안 됨 (격리 강제)
if [[ "$plan" == *"settings.json"* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); ASSERT_FAILURES+=("settings.json 잘못 포함됨"); echo "  ✗ settings.json 잘못 포함됨"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ settings.json 제외 OK"
fi

# Add: 완전 격리 (공유 없음, manual)
plan2=$(bash "$SCRIPTS/plan-build.sh" add \
  --name iso \
  --config-dir /tmp/.claude-iso \
  --shared-pool /tmp/.claude-shared \
  --shell-rc /tmp/.zshrc \
  --shell-mode manual \
  --shared "")

# 완전 격리: symlink 없음
if [[ "$plan2" == *"create_symlink"* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 완전 격리에 symlink 포함됨"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 완전 격리: symlink 없음"
fi
# manual 모드: append_block 없음
if [[ "$plan2" == *"append_block"* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ manual 모드인데 append_block 포함"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ manual 모드: append_block 없음"
fi

# Edit: 공유 항목 추가 + 제거
plan_e=$(bash "$SCRIPTS/plan-build.sh" edit \
  --name work \
  --config-dir /tmp/.claude-work \
  --shared-pool /tmp/.claude-shared \
  --add-shared CLAUDE.md \
  --remove-shared plugins)

assert_contains "$plan_e" '"action": "edit"' "action=edit"
assert_contains "$plan_e" "quarantine" "add-shared → quarantine op"
assert_contains "$plan_e" "CLAUDE.md" "CLAUDE.md path"
assert_contains "$plan_e" "remove_symlink" "remove-shared → remove_symlink"
assert_contains "$plan_e" '"op": "copy"' "remove-shared → copy"

print_summary
