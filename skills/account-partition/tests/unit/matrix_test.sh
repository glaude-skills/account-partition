#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

sb=$(make_sandbox)
trap 'cleanup_sandbox "$sb"' EXIT

# 모의 환경
mkdir -p "$sb/.claude-shared/plugins"
mkdir -p "$sb/.claude-work"
ln -s "$sb/.claude-shared/plugins" "$sb/.claude-work/plugins"
echo '{"oauthAccount":{"emailAddress":"work@example.com"}}' > "$sb/.claude-work/.claude.json"

mkdir -p "$sb/.claude-personal/plugins"   # 자체
echo '{"oauthAccount":{"emailAddress":"personal@example.com"}}' > "$sb/.claude-personal/.claude.json"

# 외부에서 settings.json 공유 (⚠ 위험 케이스)
echo "{}" > "$sb/.claude-shared/settings.json"
ln -s "$sb/.claude-shared/settings.json" "$sb/.claude-work/settings.json"

out=$(HOME="$sb" SHARED_POOL="$sb/.claude-shared" SCRIPTS_DIR="$SCRIPTS" SKIP_AUTH_STATUS=1 bash "$SCRIPTS/matrix.sh" 2>&1)

echo "--- matrix.sh output ---"
echo "$out"
echo "---"

assert_contains "$out" "claude-work" "work column"
assert_contains "$out" "claude-personal" "personal column"
assert_contains "$out" "work@example.com" "이메일 표시"
assert_contains "$out" "✓" "로그인 ✓"
assert_contains "$out" "플러그인" "플러그인 row"
assert_contains "$out" "공유" "공유 셀 표시"
assert_contains "$out" "자체" "자체 셀 표시"
assert_contains "$out" "⚠" "settings.json 공유 시 경고"
assert_contains "$out" "전역 설정" "settings.json 라벨"
assert_contains "$out" "범례" "범례 섹션"

# 빈 환경 — 계정 없음
sb2=$(make_sandbox)
trap 'cleanup_sandbox "$sb"; cleanup_sandbox "$sb2"' EXIT
out2=$(HOME="$sb2" SHARED_POOL="$sb2/.claude-shared" SCRIPTS_DIR="$SCRIPTS" SKIP_AUTH_STATUS=1 bash "$SCRIPTS/matrix.sh" 2>&1)
assert_contains "$out2" "등록된 Claude 계정이 없습니다" "빈 환경 메시지"

print_summary
