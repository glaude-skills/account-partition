---
name: login
description: "Claude CLI alias의 OAuth 로그인 — 브라우저 인증 후 자동으로 keychain·oauthAccount 저장."
---

# 계정 로그인

등록된 alias 선택 → claude auth login 호출 → 브라우저 OAuth 흐름 → 결과 검증.

## 호출 시 announce

"account-partition 스킬로 로그인을 진행할게."

## Scripts 위치 찾기

```bash
SKILL_DIR=$(ls -d ~/.claude*/plugins/cache/account-partition/account-partition/*/skills/account-partition 2>/dev/null | sort -V | tail -1)
SCRIPTS="$SKILL_DIR/scripts"
```

## 흐름

### Step 1. 계정 선택

스킬·외부 alias 모두 목록화. 각 alias의 현재 로그인 상태도 옆에 표시:

```bash
for d in $(HOME="$HOME" SHARED_POOL="$HOME/.claude-shared" bash "$SCRIPTS/discover.sh" list-dirs); do
  meta=$(bash "$SCRIPTS/discover.sh" meta "$d")
  alias=$(echo "$meta" | python3 -c "import json,sys; print(json.load(sys.stdin)['alias'])")
  status=$(CLAUDE_CONFIG_DIR="$d" claude auth status 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print('✓ ' + d.get('email','')) if d.get('loggedIn') else print('— (로그인 안 됨)')
except: print('— (확인 실패)')
")
  echo "  $alias: $status"
done
```

`AskUserQuestion` 선택지: 위 목록의 alias들. 이미 로그인된 alias도 표시(재로그인용).

### Step 2. CONFIG_DIR 결정

선택된 alias의 디렉토리 (`$HOME/.claude-<name>` 또는 default `$HOME/.claude`).

### Step 3. 활성 세션 게이트

```bash
bash "$SCRIPTS/safety.sh" check-active "<CONFIG_DIR>"
```

활성 세션 있으면 차단 + 안내.

### Step 4. claude auth login 호출 + 대기

```bash
echo "브라우저가 열립니다. Anthropic 페이지에서 인증 완료 후 자동으로 돌아옵니다..."
CLAUDE_CONFIG_DIR="<CONFIG_DIR>" claude auth login
```

(timeout 길게 — 사용자가 브라우저 인증 시간 필요)

### Step 5. 결과 검증

```bash
CLAUDE_CONFIG_DIR="<CONFIG_DIR>" claude auth status
```

JSON 파싱해서 `loggedIn=true` + email 확인. 성공이면 결과 표시:

```
✓ <alias> 로그인 완료
  email: <email>
  org: <orgName>
  subscription: <subscriptionType>
```

실패면 에러 메시지 + 재시도 안내.
