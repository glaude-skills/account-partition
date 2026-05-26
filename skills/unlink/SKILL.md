---
name: unlink
description: "Claude CLI 계정 연동 해제 — auth logout + zshrc alias 제거 + config dir 백업·제거를 단일 흐름으로 자동화."
---

# 계정 연동 해제

선택한 alias의 OAuth 로그아웃 + zshrc 라인 제거 + config dir 백업·제거를 한 번에. operation plan + 활성 세션 게이트 + 백업으로 보호.

## 호출 시 announce

"account-partition 스킬로 계정 연동 해제를 진행할게."

## Scripts 위치 찾기

이 스킬의 헬퍼 스크립트는 plugin cache 안에 있다. LLM은 첫 호출 시 다음 명령으로 위치를 찾아 `$SCRIPTS` 환경변수로 사용한다:

```bash
SKILL_DIR=$(ls -d ~/.claude*/plugins/cache/account-partition/account-partition/*/skills/account-partition 2>/dev/null | sort -V | tail -1)
SCRIPTS="$SKILL_DIR/scripts"
```

## 흐름

### Step 1. 계정 선택

```bash
bash "$SCRIPTS/shell-rc.sh" list ~/.zshrc | grep ":managed$"
```

로 스킬이 만든 alias 목록을 가져와 `AskUserQuestion`으로 선택.

외부 alias도 표시(`:external` suffix). 선택 시 안내:
"외부 alias는 v0.4에서 자동 unlink 미지원 — 명령만 출력. 진행할까요? (예/아니오)"

default `~/.claude`는 제외 (실수 방지).

### Step 2. 활성 세션 게이트

```bash
bash "$SCRIPTS/safety.sh" check-active "$HOME/.claude-<name>"
```

활성 시 차단.

### Step 3. 셸 통합 모드 — 자동/수동

`AskUserQuestion`:
```
질문: ~/.zshrc 라인을 어떻게 정리할까요?
옵션:
  - 자동 제거 (Recommended) — managed alias 블록 자동 제거
  - 수동 — 명령만 출력
```

### Step 4. Plan 생성

```bash
bash "$SCRIPTS/plan-build.sh" unlink \
  --name "<name>" \
  --config-dir "$HOME/.claude-<name>" \
  --shell-rc "$HOME/.zshrc" \
  --shell-mode "<auto|manual>" > /tmp/account-partition-plan.json
```

### Step 5. 미리보기 + 영향 안내

```bash
cat /tmp/account-partition-plan.json | bash "$SCRIPTS/plan-render.sh"
```

추가 경고:
```
이 계정의 작업기록(프로젝트·메모리·대화 기록)은 백업 안에만 남고 기본 위치에서 사라집니다.
   백업: ~/.claude-<name>.removed.<ts>.tar.gz (자동 삭제 안 함)
```

### Step 6. 최종 확인

`AskUserQuestion`:
```
질문: 진행할까요?
옵션:
  - 예 (실행)
  - 아니오 (취소)
  - 명령 출력만 (실제 변경 없이 plan을 셸 명령으로 출력)
```

### Step 7. Lock + 실행

```bash
bash "$SCRIPTS/safety.sh" lock "$HOME/.claude-<name>" "$$"

if cat /tmp/account-partition-plan.json | \
   PLAN_DIR="$HOME/.claude-shared" SCRIPTS_DIR="$SCRIPTS" \
   bash "$SCRIPTS/plan-execute.sh"; then
  STATUS=ok
else
  PLAN_DIR="$HOME/.claude-shared" SCRIPTS_DIR="$SCRIPTS" bash "$SCRIPTS/plan-rollback.sh"
  STATUS=fail
fi

bash "$SCRIPTS/safety.sh" unlock "$HOME/.claude-<name>" "$$"
```

### Step 8. 결과 출력

성공:
```
<name> 계정 연동 해제 완료
  · OAuth 로그아웃 (keychain entry 자동 정리)
  · ~/.zshrc 라인 제거
  · 계정 디렉토리 → <백업 파일 경로>

새 터미널에서 'claude-<name>' 명령이 더 이상 동작하지 않음.
복원하려면 백업 압축 해제: tar xzf <백업> -C ~ → /account-partition:add 로 재등록.
```

수동 모드이면 명령 시퀀스 출력만 (`명령 출력만` 선택과 동일하게 plan-shell-out.sh 출력).
