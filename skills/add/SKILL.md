---
name: add
description: "Claude CLI 계정 추가 연동 — 새 명령(claude-<이름>)을 감지된 모든 셸(zsh/bash/PowerShell/cmd)에 등록하고 공유 정책(토큰만 분리 포함)을 셋업. macOS·Linux·Windows."
---

# 계정 추가 연동

새 Claude CLI OAuth 계정을 위한 명령(예: 'side' → `claude-side`)을 만들고, 다른 계정과 무엇을 공유할지 골라 셋업한다. 명령은 감지된 모든 셸에 같은 정의로 동시에 기록된다.

## 호출 시 announce

"account-partition 스킬로 계정 추가 연동을 진행할게."

## UX 원칙

- 자유 텍스트 입력은 **명령어 이름 단 1곳만** (예: `side` → `claude-side`)
- 나머지 모든 결정(프리셋·기준 계정·항목 토글·셸 통합·yes/no 확인·충돌 해결)은 `AskUserQuestion`으로 (방향키 + 엔터)

## Scripts 위치 찾기

이 스킬의 헬퍼 스크립트는 plugin cache 안에 있다. 첫 호출 시 위치를 찾아 `$SCRIPTS`로 쓴다 (macOS·Linux·Windows Git Bash 공통):

```bash
SKILL_DIR=$(ls -d ~/.claude*/plugins/cache/account-partition/account-partition/*/skills/account-partition 2>/dev/null | sort -V | tail -1)
SCRIPTS="$SKILL_DIR/scripts"
```

이후 헬퍼 호출은 `bash "$SCRIPTS/<name>.sh" ...` 형식. 멀티 셸 기능은 `bash "$SCRIPTS/ap.sh" <command>`.

## §Add 흐름

### Step 1. 명령어 이름 입력 (자유 입력)

> "이 계정을 호출할 명령어 이름을 알려줘. (예: 'side' 입력 → 터미널에서 `claude-side`로 호출됨)"

검증:
- `<name>`이 `[a-zA-Z0-9_-]+` 패턴이어야 함 (아니면 다시 입력)
- 충돌 검사:
  ```bash
  HOME="$HOME" SHARED_POOL="$HOME/.claude-shared" bash "$SCRIPTS/discover.sh" list-dirs | grep -q "claude-<name>$"
  bash "$SCRIPTS/ap.sh" accounts > /tmp/ap-accounts.json
  python3 -c "import json; d=json.load(open('/tmp/ap-accounts.json')); n='<name>'; print('registry' if n in d['registry']['accounts'] else 'external' if any(e['name']==n for e in d['externals']) else 'free')"
  ```
- 이미 있으면 `AskUserQuestion`:
  ```
  질문: '<name>'은 이미 존재합니다. 어떻게 할까요?
  옵션:
    - 다른 이름으로 입력
    - (external 일 때) 기존 정의 가져오기 — account-partition:adopt 로 전환
    - (registry 일 때) 공유 항목 수정 — account-partition:edit 로 전환
    - 취소
  ```

### Step 2. 공유 정책 선택

`AskUserQuestion`:
```
질문: 다른 계정과 무엇을 공유할까요?
옵션:
  - 기본 분리 (Recommended)
      도구는 공유, 계정·작업기록·전역 설정·시크릿 분리
  - 토큰만 분리
      기존 계정과 설정·세션 목록·/resume·백그라운드 잡까지 모두 공유하고 로그인 토큰만 분리
  - 완전 격리
      아무것도 공유 안 함
  - 직접 선택
      항목별로 직접 토글 (거울 모드 = 전부 선택)
```

매핑:
- 기본 분리 → `--mode standard --shared plugins,skills,commands,agents`
- 완전 격리 → `--mode standard --shared ""`
- 직접 선택 → Step 2a 후 `--mode standard --shared <csv>`
- 토큰만 분리 → Step 2b

### Step 2a. (직접 선택) 항목별 multiSelect

`AskUserQuestion` multiSelect:
```
질문: 다른 계정과 공유할 항목을 골라줘.
옵션 (복수 선택):
  - 플러그인          설치된 플러그인 본체
  - 스킬              사용자 정의 스킬
  - 슬래시 명령       사용자 정의 단축 명령
  - 서브에이전트      사용자 정의 서브에이전트 정의
```
(글로벌 인스트럭션 `CLAUDE.md`는 "Other"에 적으면 포함. 라벨 → `plugins`, `skills`, `commands`, `agents`, `CLAUDE.md`)

**전역 설정(`settings.json`)은 격리 강제 항목이라 선택지에 노출되지 않음** (시크릿 노출 방지).

### Step 2b. (토큰만 분리) 기준 계정 선택 + 제약 안내

기준 계정 후보 = 계정 폴더(`discover.sh list-dirs`) 중 token-only 가 아닌 것 (기본 `~/.claude` 포함). `AskUserQuestion`으로 고른다 (라벨 `claude-<이름>` 또는 `claude (기본)`, description 은 폴더 경로와 이메일).

고른 직후 제약을 그대로 보여준다 (plan 의 `metadata.warnings` 와 같은 내용):

```
토큰만 분리 모드 주의사항
  · 세션 목록(←← / /resume)에서 다른 계정이 띄운 세션에 참여하면, 그 세션을 띄운 계정의 토큰이 쓰입니다.
    (Claude Code 구조상 참여는 이미 떠 있는 프로세스에 붙기만 하기 때문 — 래퍼로 바꿀 수 없음)
    계정을 바꾸려면 그 세션을 끝내고 claude-<name> --resume <세션ID> 로 다시 띄우세요.
  · 기준 계정과 설정·권한·MCP·메모리·플러그인·세션 기록을 모두 공유합니다.
  · 화면에 표시되는 계정 이메일은 공유 파일(.claude.json)에 있어 마지막에 로그인한 계정 것으로 보일 수 있습니다. 실제 토큰은 분리돼 있습니다.
```

옵션: `--mode token-only --config-dir <기준 폴더> --token-dir "$HOME/.claude-<name>"`

### Step 3. 공유 보관소 위치 (standard 이고 공유 항목이 있을 때만)

```bash
[ -d "$HOME/.claude-shared" ]
```

없으면 `AskUserQuestion`: `~/.claude-shared (Recommended)` / `다른 위치 지정`(자유 입력 절대경로). 계정 registry(`accounts.json`)도 이 보관소에 저장된다.

### Step 4. 셸 통합

먼저 대상 셸을 감지해 보여준다:

```bash
bash "$SCRIPTS/ap.sh" targets
```

`AskUserQuestion`:
```
질문: claude-<name> 명령을 어떻게 등록할까요?
옵션:
  - 감지된 모든 셸에 자동 등록 + 백업 (Recommended)
      <targets 의 kind:path 목록>. 셸마다 정의가 달라지는 일을 막는다.
  - 수동 (등록할 내용만 출력)
```

자동 → 플래그 없음, 수동 → `--manual`. `warnings`(예: `~/bin` 이 PATH 에 없음)가 있으면 함께 보여준다.

### Step 5. 활성 세션 게이트 (standard 만)

```bash
bash "$SCRIPTS/safety.sh" check-active "$HOME/.claude-<name>"
```

exit 0이면 변경 차단: "다른 Claude 세션이 실행 중입니다 (PID 출력 참고). 종료 후 다시 시도하세요."
token-only 는 기준 config 폴더를 건드리지 않으므로 게이트를 적용하지 않는다.

### Step 6. Plan 생성 + 미리보기

```bash
bash "$SCRIPTS/ap.sh" plan-add --name "<name>" --mode "<standard|token-only>" \
  --config-dir "<config 폴더>" [--token-dir "<토큰 폴더>"] \
  [--shared "<csv>"] [--shared-pool "<shared_pool>"] [--manual] > /tmp/account-partition-plan.json

cat /tmp/account-partition-plan.json | bash "$SCRIPTS/plan-render.sh"
```

`plan-render.sh` 출력을 그대로 보여준다. 수정될 셸 파일마다 한 줄씩 나오고, `metadata.warnings` 가 있으면 함께 보여준다.

### Step 7. 최종 확인

`AskUserQuestion`: `예 (실행)` / `아니오 (취소)` / `명령 출력만 (실제 변경 없이 plan을 셸 명령으로 출력)`

- "명령 출력만" → `cat /tmp/account-partition-plan.json | bash "$SCRIPTS/plan-shell-out.sh"` 출력 후 종료

### Step 8. Lock 획득 + plan 실행

```bash
LOCK_DIR="<config 폴더 또는 토큰 폴더의 부모>"   # standard: $HOME/.claude-<name>, token-only: $HOME/.claude-shared
bash "$SCRIPTS/safety.sh" lock "$LOCK_DIR" "$$"

if cat /tmp/account-partition-plan.json | \
   PLAN_DIR="$HOME/.claude-shared" SCRIPTS_DIR="$SCRIPTS" bash "$SCRIPTS/plan-execute.sh"; then
  echo "✓ 실행 완료"
else
  echo "⚠ 부분 실행 실패. 롤백 진행..."
  PLAN_DIR="$HOME/.claude-shared" SCRIPTS_DIR="$SCRIPTS" bash "$SCRIPTS/plan-rollback.sh"
fi

bash "$SCRIPTS/safety.sh" unlock "$LOCK_DIR" "$$"
```

### Step 9. 결과 출력 + 다음 안내

성공:
```
✓ 계정 폴더 생성 (token-only: 토큰 폴더만)
✓ 공유 항목 N개 연결 (standard)
✓ 셸 등록: zsh ~/.zshrc, PowerShell <profile>, cmd ~/bin/claude-<name>.cmd ... (각각 백업)
✓ 계정 registry 등록 (~/.claude-shared/accounts.json)

다음 단계:
  1) 새 터미널 열기 (이미 열린 셸은 설정을 다시 불러와야 함: zsh/bash `exec $SHELL -l`, PowerShell `. $PROFILE`)
  2) claude-<name> 실행 → 첫 실행 시 /login 으로 계정 연결
```

수동 모드면 `metadata.manual_lines` 의 `posix`(zsh/bash), `powershell`, `cmd` 블록을 셸별로 보여주고 직접 붙여넣도록 안내한다.

### Step 10. 지금 로그인할까요?

`AskUserQuestion`: `예 — 지금 바로` / `아니오 — 나중에`

"예":
```bash
echo "브라우저가 열립니다. Anthropic 페이지에서 인증 완료 후 자동으로 돌아옵니다..."
bash "$SCRIPTS/ap.sh" run "<name>" -- claude auth login
bash "$SCRIPTS/ap.sh" run "<name>" -- claude auth status
```

`ap.sh run` 은 registry 의 정의대로 env(토큰 폴더 포함)를 정확히 재현해 실행한다. 로그인 완료 보고, 실패 시 재시도 안내.

## 에러 처리

- 활성 세션 게이트 차단 → 종료 후 재시도 안내
- python3 없음 → `platform.sh` 메시지 그대로 전달 (python 3.8+ 설치 안내)
- plan-execute 실패 → 자동 롤백 (셸 파일은 백업에서 복원) + 상태 파일 위치 안내
- Windows 에서 파일 링크(`CLAUDE.md`) 실패 → 개발자 모드 안내 (디렉토리는 junction 이라 권한 불필요)
