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

### Step 1. 계정 선택 (반드시 객관식 먼저)

다른 동작 전에 alias 목록을 **객관식으로 먼저 보여주고** 사용자 선택을 받아야 한다. 임의 진행 금지.

**선택지 수집**:

```bash
MANAGED=$(bash "$SCRIPTS/shell-rc.sh" list ~/.zshrc | grep ":managed$" | cut -d: -f1)
EXTERNAL=$(bash "$SCRIPTS/shell-rc.sh" list ~/.zshrc | grep ":external$" | cut -d: -f1)
```

default `~/.claude`는 **항상 선택지에서 제외** (실수 방지). 0개면 "정리할 alias 없음" 안내 후 종료.

**`AskUserQuestion` 호출** — 최대 4개 옵션 안에:

- 각 managed alias: 라벨 `claude-<name> (스킬 관리)`, description "자동 unlink. auth_logout + zshrc 라인 제거 + config dir tar 백업 후 제거."
- 각 external alias: 라벨 `claude-<name> (외부)`, description "수동 명령 출력만. v0.4 자동 unlink 미지원."
- 마지막은 항상 **"취소"** (description "unlink 안 함, 종료")

옵션 수가 4개를 넘으면 managed 우선, external 다음, 취소는 항상 포함.

선택 결과:
- managed → Step 2로 (자동 unlink)
- external → Step 1a (수동 안내)
- 취소 → 종료

### Step 1a. 외부 alias 선택 시 (수동 안내)

자동 unlink 미지원. 다음 명령 출력 후 종료:

```bash
echo "외부 alias <name>은 v0.4에서 자동 unlink 미지원. 수동으로 다음을 진행:"
echo ""
echo "  1) OAuth 로그아웃:"
echo "     CLAUDE_CONFIG_DIR=$HOME/.claude-<name> claude auth logout"
echo ""
echo "  2) ~/.zshrc 에서 alias 라인 직접 제거 (편집기로)"
echo ""
echo "  3) 계정 디렉토리 백업 후 제거:"
echo "     tar czf ~/.claude-<name>.removed.\$(date +%Y%m%d-%H%M%S).tar.gz -C ~ .claude-<name>"
echo "     rm -rf ~/.claude-<name>"
```

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
