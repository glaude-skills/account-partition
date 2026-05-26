---
name: logout
description: "Claude CLI alias의 OAuth 로그아웃 — keychain·oauthAccount 자동 정리."
---

# 계정 로그아웃

등록된 alias 선택 → claude auth logout 호출 (완전 자동).

## 호출 시 announce

"account-partition 스킬로 로그아웃을 진행할게."

## Scripts 위치 찾기

```bash
SKILL_DIR=$(ls -d ~/.claude*/plugins/cache/account-partition/account-partition/*/skills/account-partition 2>/dev/null | sort -V | tail -1)
SCRIPTS="$SKILL_DIR/scripts"
```

## 흐름

### Step 1. 계정 선택

로그인된 alias만 표시 (logout할 가치 있는 것만):

```bash
for d in $(HOME="$HOME" SHARED_POOL="$HOME/.claude-shared" bash "$SCRIPTS/discover.sh" list-dirs); do
  status=$(CLAUDE_CONFIG_DIR="$d" claude auth status 2>/dev/null)
  logged=$(echo "$status" | python3 -c "import json,sys; print(json.load(sys.stdin).get('loggedIn', False))")
  if [ "$logged" = "True" ]; then
    alias=$(bash "$SCRIPTS/discover.sh" meta "$d" | python3 -c "import json,sys; print(json.load(sys.stdin)['alias'])")
    email=$(echo "$status" | python3 -c "import json,sys; print(json.load(sys.stdin).get('email',''))")
    echo "  $alias ($email)"
  fi
done
```

선택지 없으면 "로그인된 계정 없음" 안내.

### Step 2. 확인 객관식

```
질문: '<alias>' 로그아웃 진행할까요?
옵션:
  - 예
  - 아니오
```

### Step 3. 활성 세션 게이트

```bash
bash "$SCRIPTS/safety.sh" check-active "<CONFIG_DIR>"
```

활성 세션 있으면 차단 + 안내.

### Step 4. logout 호출

```bash
CLAUDE_CONFIG_DIR="<CONFIG_DIR>" claude auth logout
```

### Step 5. 결과 검증

```bash
CLAUDE_CONFIG_DIR="<CONFIG_DIR>" claude auth status
```

`loggedIn=false`이면 성공. 결과 표시:

```
✓ <alias> 로그아웃 완료
```

실패면 에러 메시지 + 재시도 안내.
