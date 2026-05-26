---
name: add
description: "Claude CLI 계정 추가 연동 — 새 alias 만들고 공유/격리 항목 선택해 셋업."
---

# 계정 추가 연동

새 Claude CLI OAuth 계정을 위한 alias(예: 'side' → `claude-side`)를 만들고 다른 계정과 공유할 항목을 선택해 셋업한다.

## 호출 시 announce

"account-partition 스킬로 계정 추가 연동을 진행할게."

## UX 원칙

- 자유 텍스트 입력은 **명령어 이름 단 1곳만** (예: `side` → `claude-side`)
- 나머지 모든 결정(메뉴·프리셋·항목 토글·셸 통합·yes/no 확인·충돌 해결)은 `AskUserQuestion`으로 (방향키 + 엔터)

## Scripts 위치 찾기

이 스킬의 헬퍼 스크립트는 plugin cache 안에 있다. LLM은 첫 호출 시 다음 명령으로 위치를 찾아 `$SCRIPTS` 환경변수로 사용한다:

```bash
SKILL_DIR=$(ls -d ~/.claude*/plugins/cache/account-partition/account-partition/*/skills/account-partition 2>/dev/null | sort -V | tail -1)
SCRIPTS="$SKILL_DIR/scripts"
```

이후 모든 헬퍼 호출은 `bash "$SCRIPTS/<name>.sh" ...` 형식.

## §Add 흐름 (계정 추가 연동)

### Step 1. 명령어 이름 입력 (자유 입력)

> "이 계정을 호출할 명령어 이름을 알려줘. (예: 'side' 입력 → 터미널에서 `claude-side`로 호출됨)"

검증:
- 입력 `<name>`이 `[a-zA-Z0-9_-]+` 패턴이어야 함 (그 외 거부, 다시 입력)
- 충돌 검사:
  ```bash
  HOME="$HOME" SHARED_POOL="$HOME/.claude-shared" bash "$SCRIPTS/discover.sh" list-dirs | grep -q "claude-<name>$"
  bash "$SCRIPTS/shell-rc.sh" list ~/.zshrc | grep -q "^<name>:"
  ```
- 매치 시 `AskUserQuestion`:
  ```
  질문: '<name>'은 이미 존재합니다. 어떻게 할까요?
  옵션:
    - 다른 이름으로 입력
    - 기존 항목으로 가서 공유 항목 수정 (account-partition:edit으로 전환)
    - 취소
  ```

### Step 2. 공유 정책 선택

`AskUserQuestion`:
```
질문: 다른 계정과 무엇을 공유할까요?
옵션:
  - 기본 분리 (Recommended)
      도구는 공유, 계정·작업기록·전역 설정·시크릿 분리
  - 완전 격리
      아무것도 공유 안 함
  - 거울 모드
      공유 가능한 건 다 공유 (계정만 분리)
  - 직접 선택
      항목별로 직접 토글
```

매핑 (CSV 형식 — `plan-build.sh --shared` 인자로 사용):
- 기본 분리 → `plugins,skills,commands,agents`
- 완전 격리 → (빈 문자열)
- 거울 모드 → `plugins,skills,commands,agents,CLAUDE.md`
- 직접 선택 → Step 2a

### Step 2a. (직접 선택일 때) 항목별 multiSelect

`AskUserQuestion` multiSelect:
```
질문: 다른 계정과 공유할 항목을 골라줘.
옵션 (복수 선택):
  - 플러그인          설치된 플러그인 본체
  - 스킬              사용자 정의 스킬
  - 슬래시 명령       사용자 정의 단축 명령
  - 서브에이전트      사용자 정의 서브에이전트 정의
  - 글로벌 인스트럭션  계정 전반에 적용되는 인스트럭션 문서
```

선택된 라벨 → 내부 식별자:
- 플러그인 → `plugins`
- 스킬 → `skills`
- 슬래시 명령 → `commands`
- 서브에이전트 → `agents`
- 글로벌 인스트럭션 → `CLAUDE.md`

**전역 설정(`settings.json`)은 격리 강제 항목이라 선택지에 노출되지 않음** (시크릿 노출 방지).

### Step 3. 공유 보관소 위치

보관소 존재 확인:
```bash
[ -d "$HOME/.claude-shared" ]
```

존재하지 않으면 `AskUserQuestion`:
```
질문: 공유 항목을 어디에 보관할까요? (한 번만 결정)
옵션:
  - ~/.claude-shared (Recommended)
  - 다른 위치 지정
```

"다른 위치 지정" → 자유 입력으로 절대경로 받기.

### Step 4. 셸 통합

`AskUserQuestion`:
```
질문: ~/.zshrc 에 명령어를 어떻게 추가할까요?
옵션:
  - 자동 추가 + 백업
  - 수동 (명령만 출력)
```

자동 → `--shell-mode auto`, 수동 → `--shell-mode manual`.

### Step 5. 활성 세션 게이트

```bash
bash "$SCRIPTS/safety.sh" check-active "$HOME/.claude-<name>"
```

exit 0이면 변경 차단:
```
다른 Claude 세션이 실행 중입니다 (PID 출력 참고). 종료 후 다시 시도하세요.
```

### Step 6. Plan 생성 + 미리보기

```bash
bash "$SCRIPTS/plan-build.sh" add \
  --name "<name>" \
  --config-dir "$HOME/.claude-<name>" \
  --shared-pool "<shared_pool>" \
  --shell-rc "$HOME/.zshrc" \
  --shell-mode "<auto|manual>" \
  --shared "<csv>" > /tmp/account-partition-plan.json

cat /tmp/account-partition-plan.json | bash "$SCRIPTS/plan-render.sh"
```

`plan-render.sh` stdout 그대로 사용자에게 보여줌.

### Step 7. 최종 확인

`AskUserQuestion`:
```
질문: 진행할까요?
옵션:
  - 예 (실행)
  - 아니오 (취소)
  - 명령 출력만 (실제 변경 없이 plan을 셸 명령으로 출력)
```

- "예" → Step 8
- "아니오" → 종료
- "명령 출력만" → `cat /tmp/account-partition-plan.json | bash "$SCRIPTS/plan-shell-out.sh"` 출력 후 종료

### Step 8. Lock 획득 + plan 실행

```bash
bash "$SCRIPTS/safety.sh" lock "$HOME/.claude-<name>" "$$"

if cat /tmp/account-partition-plan.json | \
   PLAN_DIR="$HOME/.claude-shared" SCRIPTS_DIR="$SCRIPTS" \
   bash "$SCRIPTS/plan-execute.sh"; then
  echo "✓ 실행 완료"
else
  echo "⚠ 부분 실행 실패. 롤백 진행..."
  PLAN_DIR="$HOME/.claude-shared" SCRIPTS_DIR="$SCRIPTS" \
    bash "$SCRIPTS/plan-rollback.sh"
fi

bash "$SCRIPTS/safety.sh" unlock "$HOME/.claude-<name>" "$$"
```

### Step 9. 결과 출력 + 다음 안내

성공:
```
✓ 계정 디렉토리 생성
✓ 공유 항목 N개 연결
[shell_mode=auto일 때] ✓ ~/.zshrc 업데이트 (백업 저장)
✓ 자격증명 토큰은 첫 로그인 시 자동으로 새 항목 생성됨

다음 단계:
  1) 새 터미널 열기 (또는 source ~/.zshrc)
  2) claude-<name> 실행 → 첫 실행 시 /login 으로 계정 연결
```

수동 셸 통합이면 추가:
```
다음 라인을 ~/.zshrc 에 추가하세요:

  # account-partition: <name>
  alias claude-<name>="CLAUDE_CONFIG_DIR=$HOME/.claude-<name> command claude"
```

### Step 10. 지금 로그인할까요? (v0.3 추가)

`AskUserQuestion`:
```
질문: 지금 OAuth 로그인할까요? (브라우저 열림)
옵션:
  - 예 — 지금 바로
  - 아니오 — 나중에 (claude-<name> 실행 후 직접 또는 /account-partition:login)
```

"예" 선택 시:
```bash
echo "브라우저가 열립니다. Anthropic 페이지에서 인증 완료 후 자동으로 돌아옵니다..."
CLAUDE_CONFIG_DIR="$HOME/.claude-<name>" claude auth login
```

이후 `claude auth status`로 검증:
```bash
CLAUDE_CONFIG_DIR="$HOME/.claude-<name>" claude auth status
```

로그인 완료 보고. 실패 시 재시도 안내.

## 에러 처리

- 활성 세션 게이트 차단 → 사용자에게 종료 후 재시도 안내
- plan-execute 실패 → 자동 롤백 + 사용자에게 보고 + 상태 파일 위치 안내
- 디스크 가득 참·권한 거부 → 명확한 에러 메시지
