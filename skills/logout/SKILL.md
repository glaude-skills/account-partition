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

### Step 1. 계정 선택 (반드시 객관식 먼저)

다른 동작 전에 로그인된 alias 목록을 **객관식으로 먼저 보여주고** 사용자 선택을 받아야 한다. 임의 진행 금지.

> **default 계정 보호 정책**: default `~/.claude` (`claude` 명령어) 는 기본 선택지에서 **제외**한다. 별도 "기본 계정(claude) 로그아웃" 옵션을 추가해 선택 시 2차 확인을 거친다.

**선택지 수집** — default `~/.claude` **제외**, `claude auth status`가 `loggedIn=true` 인 alias만:

```bash
for d in $(HOME="$HOME" SHARED_POOL="$HOME/.claude-shared" bash "$SCRIPTS/discover.sh" list-dirs); do
  # default ~/.claude 는 기본 선택지에서 제외
  if [ "$d" = "$HOME/.claude" ]; then continue; fi
  status=$(CLAUDE_CONFIG_DIR="$d" claude auth status 2>/dev/null)
  logged=$(echo "$status" | python3 -c "import json,sys; print(json.load(sys.stdin).get('loggedIn', False))")
  if [ "$logged" = "True" ]; then
    alias=$(bash "$SCRIPTS/discover.sh" meta "$d" | python3 -c "import json,sys; print(json.load(sys.stdin)['alias'])")
    email=$(echo "$status" | python3 -c "import json,sys; print(json.load(sys.stdin).get('email',''))")
    echo "  $alias ($email)"
  fi
done
```

선택지가 0개(기본 계정 옵션 포함 전)여도 "기본 계정(claude) 로그아웃" 옵션은 항상 추가된다.

**`AskUserQuestion` 호출** — 최대 4개 옵션 안에:

- 각 로그인된 alias: 라벨 `claude-<name>`, description은 `✓ <email> — 로그아웃 시 keychain·oauthAccount 자동 정리`
- 마지막에서 두 번째: **"기본 계정(claude) 로그아웃"** (description "평소 쓰는 계정에서 로그아웃됩니다 — 주의")
- 마지막: **"취소"** (description "로그아웃 안 함, 종료")

옵션 4개 넘으면 가나다 또는 등록 순으로 처음 N개, "기본 계정"·취소는 항상 포함.

선택 결과:
- alias → Step 2 (한 번 더 확인)
- 기본 계정(claude) 로그아웃 → **Step 1a (2차 확인)**
- 취소 → 종료

### Step 1a. 기본 계정 2차 확인

`AskUserQuestion`:
```
질문: 평소 쓰는 계정에서 로그아웃됩니다. 진행할까요?
옵션:
  - 예, 기본 계정(~/.claude)에서 로그아웃
  - 아니오 (취소)
```

확인 시 CONFIG_DIR = `$HOME/.claude` 로 Step 2 진행.

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
