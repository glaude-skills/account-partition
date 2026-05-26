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

# Unlink: shell-mode=auto → auth_logout + remove_block + archive_dir + remove_dir (분리)
plan_u=$(bash "$SCRIPTS/plan-build.sh" unlink \
  --name test \
  --config-dir /tmp/.claude-test \
  --shell-rc /tmp/.zshrc \
  --shell-mode auto)

assert_contains "$plan_u" '"action": "unlink"' "action=unlink"
assert_contains "$plan_u" '"op": "auth_logout"' "auth_logout op"
assert_contains "$plan_u" '"op": "remove_block"' "remove_block op"
assert_contains "$plan_u" '"op": "archive_dir"' "archive_dir op"
assert_contains "$plan_u" '"op": "remove_dir"' "remove_dir op (archive 후 별도 분리)"
# archive_dir에 remove_after 없어야 함
if [[ "$plan_u" == *'"remove_after"'* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); ASSERT_FAILURES+=("archive_dir에 remove_after 잔존"); echo "  ✗ archive_dir에 remove_after 잔존"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ archive_dir에 remove_after 없음 (remove_dir로 분리됨)"
fi

# Unlink: manual 모드 → auth_logout은 항상 포함, remove_block만 빠짐, archive_dir + remove_dir 포함
plan_u2=$(bash "$SCRIPTS/plan-build.sh" unlink \
  --name test2 \
  --config-dir /tmp/.claude-test2 \
  --shell-rc /tmp/.zshrc \
  --shell-mode manual)

assert_contains "$plan_u2" '"op": "auth_logout"' "manual에도 auth_logout 포함 (v0.4.1: shell-mode 무관)"
if [[ "$plan_u2" == *'"op": "remove_block"'* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); ASSERT_FAILURES+=("manual 모드에 remove_block 포함"); echo "  ✗ manual 모드에 remove_block 포함"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ manual: remove_block 없음 (zshrc는 사용자가 수동)"
fi
assert_contains "$plan_u2" '"op": "archive_dir"' "manual에도 archive_dir은 있음"
assert_contains "$plan_u2" '"op": "remove_dir"' "manual에도 remove_dir은 있음 (분리됨)"

print_summary
