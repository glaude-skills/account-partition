---
name: unlink
description: "Claude CLI 계정 연동 해제 — 로그아웃(또는 토큰 폴더 정리) + 모든 셸의 claude-<이름> 정의 제거 + 폴더 백업·제거를 단일 흐름으로 자동화. macOS·Linux·Windows."
---

# 계정 연동 해제

선택한 계정의 로그아웃 + 모든 셸(zsh/bash/PowerShell/cmd 래퍼)의 정의 제거 + 폴더 백업·제거를 한 번에. operation plan + 활성 세션 게이트 + 백업으로 보호.

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
bash "$SCRIPTS/ap.sh" accounts > /tmp/ap-accounts.json
# REGISTRY: v0.5 계정 registry(~/.claude-shared/accounts.json) — 모든 셸에서 자동 정리
python3 -c "import json; d=json.load(open('/tmp/ap-accounts.json', encoding='utf-8')); [print(n, a['mode'], a['config_dir'], a.get('token_dir') or '') for n, a in d['registry']['accounts'].items()]"
# LEGACY: v0.4 로 만든 zsh 관리 블록 (registry 에 없음)
MANAGED=$(bash "$SCRIPTS/shell-rc.sh" list ~/.zshrc | grep ":managed$" | cut -d: -f1)
# EXTERNAL: 손으로 만든 정의 (모든 셸)
python3 -c "import json; d=json.load(open('/tmp/ap-accounts.json', encoding='utf-8')); [print(e['name']) for e in d['externals'] if not e['in_registry']]"
```

default `~/.claude`는 **항상 선택지에서 제외** (실수 방지). 0개면 "정리할 alias 없음" 안내 후 종료.

**`AskUserQuestion` 호출** — 최대 4개 옵션 안에:

- 각 registry 계정: 라벨 `claude-<name>`, description 은 모드별로
  - 일반: "자동. 로그아웃 + 모든 셸 정의 제거 + config 폴더 tar 백업 후 제거"
  - 토큰만 분리: "자동. 토큰 폴더 tar 백업 후 제거 + 모든 셸 정의 제거. 공유 config 폴더는 그대로"
  - 기본 계정(`~/.claude`)을 쓰는 정의: "셸 정의만 제거 (기본 계정은 로그아웃·삭제 안 함)"
- 각 LEGACY(v0.4 zsh 관리) alias: 라벨 `claude-<name> (v0.4)`, description "자동 unlink (zsh)"
- 각 external: 라벨 `claude-<name> (외부)`, description "먼저 가져오기(adopt) 후 자동 unlink 가능"
- 마지막은 항상 **"취소"** (description "unlink 안 함, 종료")

옵션 수가 4개를 넘으면 managed 우선, external 다음, 취소는 항상 포함.

선택 결과:
- registry 계정 → Step 3R (registry 경로)
- v0.4 managed → Step 2로 (기존 자동 unlink)
- external → `AskUserQuestion` "가져온 뒤 unlink / 수동 안내 / 취소". 가져오기는 account-partition:adopt 실행 후 이 스킬로 돌아온다. 수동은 Step 1a
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

### Step 3R. (registry 계정) Plan 생성

```bash
bash "$SCRIPTS/ap.sh" plan-unlink --name "<name>" > /tmp/account-partition-plan.json
```

- 토큰만 분리 계정이 기대고 있는 기준 계정이면 plan 생성이 **거부**된다 (공유 config 폴더 보호). 메시지에 나온 의존 계정을 먼저 unlink 하라고 안내하고 종료.
- 일반 계정이면 plan 의 `preconditions` 에 활성 세션 게이트가 들어 있다 → Step 2 의 check-active 를 `<config 폴더>` 로 실행.
- 토큰만 분리 계정은 `claude auth logout` 대신 토큰 폴더를 아카이브한다 (logout 이 공유 `.claude.json` 의 표시 계정까지 지울 수 있기 때문). macOS 는 해당 키체인 항목도 삭제.

이후 Step 4 (미리보기)부터 같다. 결과 출력은 "모든 셸에서 claude-<name> 제거" 로 안내.

### Step 2. 활성 세션 게이트

```bash
bash "$SCRIPTS/safety.sh" check-active "$HOME/.claude-<name>"
```

활성 시 차단.

### Step 3. Plan 생성

managed alias unlink는 **항상 자동 모드**. 사용자에게 zshrc 정리 방식을 묻지 않음. (외부 alias는 §Step 1a에서 이미 수동 분기 처리.)

```bash
bash "$SCRIPTS/plan-build.sh" unlink \
  --name "<name>" \
  --config-dir "$HOME/.claude-<name>" \
  --shell-rc "$HOME/.zshrc" \
  --shell-mode auto > /tmp/account-partition-plan.json
```

### Step 4. 미리보기 + 영향 안내

```bash
cat /tmp/account-partition-plan.json | bash "$SCRIPTS/plan-render.sh"
```

추가 경고:
```
이 계정의 작업기록(프로젝트·메모리·대화 기록)은 백업 안에만 남고 기본 위치에서 사라집니다.
   백업: ~/.claude-<name>.removed.<ts>.tar.gz (자동 삭제 안 함)
```

### Step 5. 최종 확인

`AskUserQuestion`:
```
질문: 진행할까요?
옵션:
  - 예 (실행)
  - 아니오 (취소)
  - 명령 출력만 (실제 변경 없이 plan을 셸 명령으로 출력)
```

### Step 6. Lock + 실행

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

### Step 7. 결과 출력

성공:
```
<name> 계정 연동 해제 완료
  · OAuth 로그아웃 (keychain entry 자동 정리)
  · 셸 정의 제거 (zsh/bash/PowerShell/cmd 래퍼 — 각 파일 백업)
  · 계정 디렉토리 → <백업 파일 경로>

새 터미널에서 'claude-<name>' 명령이 더 이상 동작하지 않음.
복원하려면 백업 압축 해제: tar xzf <백업> -C ~ → /account-partition:add 로 재등록.
```

최종 확인에서 "명령 출력만" 선택 시 plan-shell-out.sh로 셸 시퀀스만 출력하고 종료.
