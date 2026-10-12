---
name: adopt
description: "손으로 만든 claude-<이름> 정의(셸 alias·함수, PowerShell 함수, ~/bin 래퍼)를 스킬 관리로 가져와 모든 셸에 같은 정의로 통일. 셸마다 정의가 달라 계정이 섞이는 문제 해결."
---

# 기존 정의 가져오기 (adopt)

스킬이 만들지 않은 `claude-<이름>` 정의를 찾아 해석하고, 고른 정의 하나로 모든 셸(zsh/bash/PowerShell/cmd 래퍼)을 통일한 뒤 계정 registry 에 등록한다. 이후 add 로 만든 계정과 똑같이 list/unlink/login/logout 으로 관리된다.

## 호출 시 announce

"account-partition 스킬로 기존 정의 가져오기를 진행할게."

## Scripts 위치 찾기

```bash
SKILL_DIR=$(ls -d ~/.claude*/plugins/cache/account-partition/account-partition/*/skills/account-partition 2>/dev/null | sort -V | tail -1)
SCRIPTS="$SKILL_DIR/scripts"
```

## 흐름

### Step 1. 외부 정의 조회

```bash
bash "$SCRIPTS/ap.sh" accounts > /tmp/ap-accounts.json
python3 - <<'EOF'
import json
d = json.load(open('/tmp/ap-accounts.json', encoding='utf-8'))
for e in d['externals']:
    if e['in_registry']:
        continue
    print(f"claude-{e['name']}:")
    for i, v in enumerate(e['variants']):
        df = v['definition']
        srcs = ', '.join(f"{s['kind']}:{s['file']}" for s in v['sources'])
        print(f"  [{i}] config={df['config_dir']} 토큰={df['token_dir'] or '(config와 같음)'} env={df['extra_env']}  ← {srcs}")
    for u in e['unparseable']:
        print(f"  [해석 불가] {u['kind']}:{u['file']} — {u['reason']}")
EOF
```

외부 정의가 없으면 "가져올 정의가 없습니다" 후 종료.

### Step 2. 가져올 이름 선택

`AskUserQuestion` (multiSelect, 해석 가능한 이름만): 라벨 `claude-<이름>`, description 은 정의 요약(정의가 여러 개면 "셸마다 정의가 다름 — 다음 단계에서 선택"). 해석 불가만 있는 이름은 선택지에서 빼고 "직접 정리 필요" 로 따로 안내한다.

### Step 3. (정의가 여러 개인 이름마다) 어느 정의로 통일할지

예:
```
질문: claude-dami 정의가 셸마다 다릅니다. 어느 정의로 통일할까요?
옵션:
  - PowerShell 쪽 — config=~/.claude-work, 토큰=~/.claude-dami (토큰만 분리)
  - 래퍼(cmd/sh) 쪽 — config=~/.claude-dami (완전 분리)
  - 건너뛰기
```

선택한 variant 의 `signature` 를 쓰거나, 출처 셸 종류(`powershell`/`posix`/`cmd`/`sh`)로 고른다. 해석 불가 정의가 섞인 이름은 자동 가져오기가 거부되므로 먼저 수동 정리를 안내한다.

### Step 4. plan 생성 + 미리보기 (이름마다)

```bash
bash "$SCRIPTS/ap.sh" plan-adopt --name "<name>" [--from-kind <kind> | --signature '<signature>'] > /tmp/ap-adopt-<name>.json
cat /tmp/ap-adopt-<name>.json | bash "$SCRIPTS/plan-render.sh"
```

미리보기에는 외부 정의 제거(백업), 셸별 관리 블록 기록, 래퍼 교체(백업), registry 등록이 나온다. token-only 로 판별되면 제약 경고(세션 참여 시 띄운 계정 토큰 사용 등)도 함께 나온다.

### Step 5. 확인 후 실행

`AskUserQuestion`: `예 (실행)` / `아니오 (취소)`

```bash
if cat /tmp/ap-adopt-<name>.json | PLAN_DIR="$HOME/.claude-shared" SCRIPTS_DIR="$SCRIPTS" bash "$SCRIPTS/plan-execute.sh"; then
  echo "✓ claude-<name> 가져오기 완료"
else
  PLAN_DIR="$HOME/.claude-shared" SCRIPTS_DIR="$SCRIPTS" bash "$SCRIPTS/plan-rollback.sh"
fi
```

adopt 는 계정 폴더를 건드리지 않으므로 활성 세션 게이트를 적용하지 않는다 (실행 중인 Claude 세션이 있어도 안전). 단, 이미 열린 셸은 새 정의를 다시 불러와야 한다.

### Step 6. 결과 + 검증 안내

```
✓ 외부 정의 제거 (백업: <file>.bak.<ts>)
✓ 셸 등록: ...
✓ registry 등록

새 터미널에서 확인:
  bash "$SCRIPTS/ap.sh" env <name>        # 이 계정이 넘길 env
  claude-<name> auth status                # 실제 로그인 계정
```

## 해석 규칙 요약

- 인식: `VAR=값` / `export` / `$env:VAR = ...` / `set "VAR=값"` / `Remove-Item Env:VAR` / `unset` / `env -u` + `claude` 호출
- 경로의 `$HOME`, `~`, `$USERPROFILE`, `%USERPROFILE%`, `$env:USERPROFILE`, `(Join-Path $HOME '...')` 는 홈 기준으로 정규화
- `CLAUDE_CONFIG_DIR`, `CLAUDE_SECURESTORAGE_CONFIG_DIR` 외 변수(예: `CLAUDE_PROFILE`)는 보존해서 모든 셸 블록에 넣는다
- 조건문·다른 명령이 섞이면 해석 불가 — 손대지 않는다
- 정의 바로 위에 붙은 주석 줄은 함께 지운다 (백업에 남음)
