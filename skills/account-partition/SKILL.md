---
name: account-partition
description: "Claude CLI를 여러 OAuth 계정용으로 분리·관리하는 스킬. v1은 추가·조회·공유 항목 수정."
---

# account-partition (v1)

여러 Claude CLI OAuth 계정을 한 머신에서 `CLAUDE_CONFIG_DIR` alias로 분리해 호출하고, 계정 사이의 공유/격리 항목을 사용자가 선택할 수 있게 한다.

## 호출 시 announce

"account-partition 스킬을 사용해 [선택한 액션]을 진행할게."

## UX 원칙

- 자유 텍스트 입력은 **명령어 이름 단 1곳만** (예: `side` → `claude-side`)
- 나머지 모든 결정(메뉴·프리셋·항목 토글·셸 통합·yes/no 확인·충돌 해결·계정 선택)은 `AskUserQuestion`으로 (방향키 + 엔터)

## Scripts 위치 찾기

이 스킬의 헬퍼 스크립트는 plugin cache 안에 있다. LLM은 첫 호출 시 다음 명령으로 위치를 찾아 `$SCRIPTS` 환경변수로 사용한다:

```bash
SKILL_DIR=$(ls -d ~/.claude*/plugins/cache/account-partition/account-partition/*/skills/account-partition 2>/dev/null | sort -V | tail -1)
SCRIPTS="$SKILL_DIR/scripts"
```

이후 모든 헬퍼 호출은 `bash "$SCRIPTS/<name>.sh" ...` 형식.

## 메인 메뉴

`AskUserQuestion` 호출:

```
질문: 무엇을 할까요?
옵션:
  - 계정 추가 연동
  - 계정 조회
  - 계정의 공유 항목 수정
  - 계정 연동 해제   (v1 미지원 — 선택 시 안내만)
```

선택에 따라 분기:
- "계정 추가 연동" → §Add 흐름
- "계정 조회" → §List 흐름
- "계정의 공유 항목 수정" → §Edit 흐름
- "계정 연동 해제" → 다음 안내 후 종료:
  ```
  계정 연동 해제는 v1에서 자동화하지 않습니다. 다음을 수동으로 진행하세요:
  1) ~/.zshrc 에서 alias claude-<name> 라인 제거
  2) ~/.claude-<name>/ 디렉토리 백업 후 제거
  3) (선택) keychain 항목 수동 제거:
     security delete-generic-password -s "Claude Code-credentials-<hash>"
  ```

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
    - 기존 항목으로 가서 공유 항목 수정 (§Edit으로 전환)
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

## §List 흐름 (계정 조회)

```bash
HOME="$HOME" SHARED_POOL="$HOME/.claude-shared" SCRIPTS_DIR="$SCRIPTS" \
  bash "$SCRIPTS/matrix.sh"
```

stdout 그대로 출력. 부가 정보 함께:

### 무시된 후보

```bash
HOME="$HOME" SHARED_POOL="$HOME/.claude-shared" bash "$SCRIPTS/discover.sh" list-ignored
```

결과 있으면 "무시된 후보 (계정 조건 미충족)" 섹션으로 표시.

### 보관 중인 백업

```bash
find "$HOME" -maxdepth 2 \( -name "*.bak.*" -o -name "*.removed.*" \) 2>/dev/null
find "$HOME" -maxdepth 3 -name ".account-partition-quarantine" -type d 2>/dev/null
```

발견된 개수와 위치 안내. 정리는 사용자 수동.

## §Edit 흐름 (계정의 공유 항목 수정)

### Step 1. 계정 선택

스킬 관리 계정만:
```bash
bash "$SCRIPTS/shell-rc.sh" list ~/.zshrc | grep ":managed$" | cut -d: -f1
```

`AskUserQuestion`:
```
질문: 어떤 계정을 수정할까요?
옵션: [위 명령 결과 각각]
```

외부 alias도 표시(`:external` suffix)되면 선택 시 안내:
```
외부에서 만든 alias는 v1에서 자동 수정 미지원. 수동 명령 출력만 가능.
계속할까요? (예 / 아니오)
```

### Step 2. 현재 상태 기반 토글

각 토글 가능 항목에 대해 현재 상태 계산:
```bash
for item in plugins skills commands agents CLAUDE.md; do
  path="$HOME/.claude-<name>/$item"
  if [ -L "$path" ] && [[ "$(readlink "$path")" == "$HOME/.claude-shared/"* ]]; then
    echo "$item: shared"
  elif [ -e "$path" ]; then
    echo "$item: isolated"
  else
    echo "$item: absent"
  fi
done
```

`AskUserQuestion` multiSelect (현재 공유 항목은 체크된 상태):
```
질문: '<name>'의 공유 항목 (체크 = 공유, 끄면 격리)
옵션:
  - 플러그인          [현재 상태에 따라 체크]
  - 스킬              ...
  - 슬래시 명령       ...
  - 서브에이전트      ...
  - 글로벌 인스트럭션 ...
```

비교해서:
- 새로 켜진 항목 → `add_shared` (CSV)
- 새로 꺼진 항목 → `remove_shared` (CSV)

### Step 3. 충돌 검사

`add_shared`의 각 항목에 대해 공유 보관소에 이미 존재 여부 확인:
```bash
[ -e "$HOME/.claude-shared/<item>" ]
```

존재하면 충돌. `AskUserQuestion`:
```
질문: '<item>'은 공유 보관소에 이미 있습니다. 어떻게 할까요?
옵션:
  - 공유 본 보존 (Recommended) — 계정 사본은 격리 보존(.account-partition-quarantine/)으로 이동
  - 사본으로 덮어쓰기 — ⚠ 영향: 다음 alias들이 새 본을 보게 됨: <영향 alias 목록>
  - 이 항목만 변경 취소
```

영향받는 alias 목록은 다른 계정 디렉토리에서 같은 항목이 공유 보관소를 향해 symlink되어 있는지 스캔:
```bash
for d in $(HOME="$HOME" SHARED_POOL="$HOME/.claude-shared" bash "$SCRIPTS/discover.sh" list-dirs); do
  if [ -L "$d/<item>" ] && [[ "$(readlink "$d/<item>")" == "$HOME/.claude-shared/<item>" ]]; then
    basename "$d"
  fi
done
```

### Step 4. Plan 생성 + 미리보기 + 실행

§Add Step 5~9와 같은 패턴. 단 `plan-build.sh edit ...` 사용:

```bash
bash "$SCRIPTS/plan-build.sh" edit \
  --name "<name>" \
  --config-dir "$HOME/.claude-<name>" \
  --shared-pool "$HOME/.claude-shared" \
  --add-shared "<csv>" \
  --remove-shared "<csv>" > /tmp/account-partition-plan.json
```

이후 동일 흐름 (미리보기 → 최종 확인 → lock → execute → unlock → 결과).

공유 본 덮어쓰기 작업이 포함된 경우 미리보기 후 추가 확인:
```
질문: 이 작업은 다른 alias에도 영향을 줍니다 (위 영향 alias 목록). 정말 진행할까요?
옵션: 예 / 아니오
```

## 에러 처리

- 활성 세션 게이트 차단 → 사용자에게 종료 후 재시도 안내
- plan-execute 실패 → 자동 롤백 + 사용자에게 보고 + 상태 파일 위치 안내
- 디스크 가득 참·권한 거부 → 명확한 에러 메시지

## 보안 안내 (수시)

- `settings.json` 공유 시도가 발견되면(외부 환경) 매트릭스에 `⚠ 공유` 표시
- "MCP 토큰·외부 자격증명이 모든 계정에 노출되어 있습니다" 경고
- v1은 자동 분리 미지원. 수동 명령 안내:
  ```
  cp ~/.claude-shared/settings.json ~/.claude-<name>/settings.json
  rm ~/.claude-<name>/.. # symlink 제거 (계정마다)
  ```
