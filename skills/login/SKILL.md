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

### Step 1. 계정 선택 (반드시 객관식 먼저)

다른 동작 전에 alias 목록을 **객관식으로 먼저 보여주고** 사용자 선택을 받아야 한다. 임의 진행 금지.

**선택지 수집** — 모든 등록된 alias + 현재 로그인 상태:

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

**`AskUserQuestion` 호출** — 최대 4개 옵션 안에:

- 각 alias: 라벨 `claude-<name>` (또는 default는 `claude (기본)`), description은 위 status 결과 (`✓ <email>` 또는 `— (로그인 안 됨)`)
- 마지막은 항상 **"취소"** (description "로그인 안 함, 종료")

이미 로그인된 alias도 선택지에 포함 (재로그인용). 옵션 4개 넘으면 미로그인 alias 우선, 취소는 항상 포함.

선택 결과:
- alias → Step 2로
- 취소 → 종료

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
