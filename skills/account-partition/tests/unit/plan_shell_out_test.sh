#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

plan='{"metadata":{"action":"add","alias_name":"side"},"operations":[{"op":"create_dir","path":"/tmp/test-side","mode":"0700"},{"op":"create_symlink","src":"/tmp/shared/plugins","dst":"/tmp/test-side/plugins","backup_if_exists":true},{"op":"append_block","file":"/tmp/.zshrc","marker":"# account-partition: side","lines":["alias claude-side=\"x\""],"backup":true}]}'

out=$(echo "$plan" | bash "$SCRIPTS/plan-shell-out.sh")

echo "--- plan-shell-out output ---"
echo "$out"
echo "---"

assert_contains "$out" "mkdir -p" "mkdir 명령"
assert_contains "$out" "/tmp/test-side" "create_dir path"
assert_contains "$out" "chmod 0700" "chmod 명령"
assert_contains "$out" "ln -s" "symlink 명령"
assert_contains "$out" "/tmp/shared/plugins" "symlink src"
assert_contains "$out" "/tmp/test-side/plugins" "symlink dst"
assert_contains "$out" "cp -p /tmp/.zshrc" "백업 명령"
assert_contains "$out" "alias claude-side" "alias 본문"
assert_contains "$out" "set -e" "안전성 set -e"

# 특수문자 escape (shell injection 차단)
plan_special='{"metadata":{"action":"add","alias_name":"x"},"operations":[{"op":"create_dir","path":"/tmp/with space; rm -rf /","mode":"0700"}]}'
out_s=$(echo "$plan_special" | bash "$SCRIPTS/plan-shell-out.sh")
# 위험한 토큰이 quote 처리되어야 함
assert_contains "$out_s" "'/tmp/with space; rm -rf /'" "shell quoting (특수문자)"

# remove_symlink op
plan_rm='{"metadata":{"action":"edit","alias_name":"w"},"operations":[{"op":"remove_symlink","dst":"/tmp/x"}]}'
out_rm=$(echo "$plan_rm" | bash "$SCRIPTS/plan-shell-out.sh")
assert_contains "$out_rm" "rm /tmp/x" "remove_symlink → rm"

# quarantine op (config_dir 기반)
plan_q='{"metadata":{"action":"edit","alias_name":"w"},"operations":[{"op":"quarantine","path":"/tmp/.claude-w/CLAUDE.md","config_dir":"/tmp/.claude-w"}]}'
out_q=$(echo "$plan_q" | bash "$SCRIPTS/plan-shell-out.sh")
assert_contains "$out_q" "/tmp/.claude-w/.account-partition-quarantine" "quarantine 디렉토리"
assert_contains "$out_q" "mv /tmp/.claude-w/CLAUDE.md" "quarantine mv"

# copy op
plan_cp='{"metadata":{"action":"edit","alias_name":"w"},"operations":[{"op":"copy","src":"/a","dst":"/b"}]}'
out_cp=$(echo "$plan_cp" | bash "$SCRIPTS/plan-shell-out.sh")
assert_contains "$out_cp" "cp -Rp /a /b" "copy → cp -Rp (디렉토리 가능성)"

# archive_dir op (remove_after=true)
plan_sh='{"metadata":{"action":"unlink","alias_name":"x"},"operations":[{"op":"archive_dir","src":"/tmp/.x","remove_after":true}]}'
out_sh=$(echo "$plan_sh" | bash "$SCRIPTS/plan-shell-out.sh")
assert_contains "$out_sh" "tar czf" "tar 명령"
assert_contains "$out_sh" "rm -rf /tmp/.x" "원본 제거"

# auth_logout op
plan_al='{"metadata":{"action":"unlink","alias_name":"y"},"operations":[{"op":"auth_logout","config_dir":"/tmp/.y"}]}'
out_al=$(echo "$plan_al" | bash "$SCRIPTS/plan-shell-out.sh")
assert_contains "$out_al" "claude auth logout" "auth logout 명령"
assert_contains "$out_al" "CLAUDE_CONFIG_DIR" "CLAUDE_CONFIG_DIR 설정"

print_summary
