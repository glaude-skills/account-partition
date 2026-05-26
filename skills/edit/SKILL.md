---
name: edit
description: "Claude CLI 계정의 공유 항목 수정 — 공유 ↔ 격리 토글, 충돌 해결."
---

# 계정의 공유 항목 수정

기존 alias의 공유/격리 항목을 토글한다. 충돌 발생 시 사용자에게 해결 옵션 제시.

## 호출 시 announce

"account-partition 스킬로 공유 항목 수정을 진행할게."

## UX 원칙

- 나머지 모든 결정(계정 선택·항목 토글·yes/no 확인·충돌 해결)은 `AskUserQuestion`으로 (방향키 + 엔터)

## Scripts 위치 찾기

이 스킬의 헬퍼 스크립트는 plugin cache 안에 있다. LLM은 첫 호출 시 다음 명령으로 위치를 찾아 `$SCRIPTS` 환경변수로 사용한다:

```bash
SKILL_DIR=$(ls -d ~/.claude*/plugins/cache/account-partition/account-partition/*/skills/account-partition 2>/dev/null | sort -V | tail -1)
SCRIPTS="$SKILL_DIR/scripts"
```

이후 모든 헬퍼 호출은 `bash "$SCRIPTS/<name>.sh" ...` 형식.

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
