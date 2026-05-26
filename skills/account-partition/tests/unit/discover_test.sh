#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

sb=$(make_sandbox)
trap 'cleanup_sandbox "$sb"' EXIT

# 일반 alias 디렉토리
mkdir -p "$sb/.claude-work"
echo '{"oauthAccount":{"emailAddress":"test@example.com"}}' > "$sb/.claude-work/.claude.json"
mkdir -p "$sb/.claude-personal"
echo '{"oauthAccount":{"emailAddress":"other@example.com"}}' > "$sb/.claude-personal/.claude.json"

# 공유 보관소 (제외)
mkdir -p "$sb/.claude-shared"

# 비-디렉토리
touch "$sb/.claude.json"

# 백업 잔존물 (제외)
touch "$sb/.claude-side.removed.20260101.tar.gz"
mkdir -p "$sb/.claude-old"   # .claude.json 없음 → 후보 미충족

# default ~/.claude
mkdir -p "$sb/.claude"

# list-dirs
out=$(HOME="$sb" SHARED_POOL="$sb/.claude-shared" bash "$SCRIPTS/discover.sh" list-dirs 2>&1)

echo "--- list-dirs output ---"
echo "$out"
echo "---"

assert_contains "$out" ".claude-work" "발견: .claude-work"
assert_contains "$out" ".claude-personal" "발견: .claude-personal"

# default ~/.claude — .claude.json 없어도 special case로 포함되어야 함 (design §13)
# (위에서 mkdir -p "$sb/.claude" 만 하고 .claude.json 미생성)
default_included=false
while IFS= read -r line; do
  if [[ "$line" == "$sb/.claude" ]]; then
    default_included=true
    break
  fi
done <<< "$out"

if $default_included; then
  ASSERT_PASS=$((ASSERT_PASS + 1)); echo "  ✓ default ~/.claude special-case 포함 OK"
else
  ASSERT_FAIL=$((ASSERT_FAIL + 1)); ASSERT_FAILURES+=("default ~/.claude 미포함"); echo "  ✗ default ~/.claude 미포함 — special case 누락"
fi

# 제외 검증
if [[ "$out" == *".claude-shared"* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL + 1)); ASSERT_FAILURES+=(".claude-shared 잘못 포함됨")
  echo "  ✗ .claude-shared 잘못 포함됨"
else
  ASSERT_PASS=$((ASSERT_PASS + 1)); echo "  ✓ .claude-shared 제외 OK"
fi

# 무시된 후보
out_ignored=$(HOME="$sb" SHARED_POOL="$sb/.claude-shared" bash "$SCRIPTS/discover.sh" list-ignored 2>&1)
assert_contains "$out_ignored" ".claude-old" ".claude-old는 무시된 후보로 표시"

# meta
mkdir -p "$sb/.claude-meta-test"
echo '{"oauthAccount":{"emailAddress":"meta@example.com"}}' > "$sb/.claude-meta-test/.claude.json"
meta=$(bash "$SCRIPTS/discover.sh" meta "$sb/.claude-meta-test")
assert_contains "$meta" "meta@example.com" "meta JSON에 email 포함"
assert_contains "$meta" "claude-meta-test" "meta JSON에 alias 이름 포함"

print_summary
