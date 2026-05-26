#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

plan=$(cat <<'JSON'
{
  "metadata": {
    "action": "add",
    "alias_name": "side",
    "config_dir": "/Users/test/.claude-side",
    "shared_pool": "/Users/test/.claude-shared"
  },
  "operations": [
    {"op": "create_dir", "path": "/Users/test/.claude-side", "mode": "0700"},
    {"op": "create_symlink", "src": "/Users/test/.claude-shared/plugins", "dst": "/Users/test/.claude-side/plugins"},
    {"op": "create_symlink", "src": "/Users/test/.claude-shared/CLAUDE.md", "dst": "/Users/test/.claude-side/CLAUDE.md"},
    {"op": "append_block", "file": "/Users/test/.zshrc", "marker": "# account-partition: side", "lines": ["alias claude-side=\"CLAUDE_CONFIG_DIR=/Users/test/.claude-side command claude\""], "backup": true}
  ]
}
JSON
)

out=$(echo "$plan" | bash "$SCRIPTS/plan-render.sh")

echo "--- plan-render output ---"
echo "$out"
echo "---"

assert_contains "$out" "계정 추가" "헤더에 액션 한국어 표시"
assert_contains "$out" "claude-side" "alias 이름 표시"
assert_contains "$out" "생성" "create_dir → '생성'"
assert_contains "$out" "공유" "create_symlink → '공유'"
assert_contains "$out" "플러그인" "plugins 라벨 한국어"
assert_contains "$out" "글로벌 인스트럭션" "CLAUDE.md 라벨 한국어"
assert_contains "$out" "/Users/test/.claude-shared/plugins" "심볼릭 대상 경로 표시"
assert_contains "$out" "추가" "append_block → '추가'"
assert_contains "$out" "백업" "backup=true → 백업 안내"
assert_contains "$out" "예 / 아니오 / 명령 출력만" "최종 확인 3지 객관식 안내"

# Edit 액션 라벨
plan_edit='{"metadata":{"action":"edit","alias_name":"work","config_dir":"/t/.claude-work"},"operations":[]}'
out_e=$(echo "$plan_edit" | bash "$SCRIPTS/plan-render.sh")
assert_contains "$out_e" "공유 항목 수정" "edit 액션 한국어 라벨"

# quarantine op
plan_q='{"metadata":{"action":"edit","alias_name":"work"},"operations":[{"op":"quarantine","path":"/t/.claude-work/CLAUDE.md","config_dir":"/t/.claude-work"}]}'
out_q=$(echo "$plan_q" | bash "$SCRIPTS/plan-render.sh")
assert_contains "$out_q" "격리 보존" "quarantine → '격리 보존'"

# unlink 액션 + 새 op 라벨 검증
plan_unlink='{"metadata":{"action":"unlink","alias_name":"x"},"operations":[{"op":"auth_logout","config_dir":"/tmp/.x"},{"op":"remove_block","file":"/tmp/.zshrc","marker":"# account-partition: x"},{"op":"archive_dir","src":"/tmp/.x","remove_after":true}]}'
out_u=$(echo "$plan_unlink" | bash "$SCRIPTS/plan-render.sh")

echo "--- plan-render unlink output ---"
echo "$out_u"
echo "---"

assert_contains "$out_u" "연동 해제" "unlink action 라벨"
assert_contains "$out_u" "로그아웃" "auth_logout 라벨"
assert_contains "$out_u" "제거" "remove_block 라벨"
assert_contains "$out_u" "아카이브" "archive_dir 라벨"
assert_contains "$out_u" "원본 제거" "archive_dir remove_after=true 라벨"

print_summary
