---
name: list
description: "Claude CLI 연동된 계정 조회 — 공유/격리 매트릭스 + 시크릿 노출 경고."
---

# 계정 조회

연동된 모든 Claude CLI 계정과 공유/격리 매트릭스를 표로 표시한다. 읽기 전용.

## 호출 시 announce

"account-partition 스킬로 계정 조회를 진행할게."

## Scripts 위치 찾기

이 스킬의 헬퍼 스크립트는 plugin cache 안에 있다. LLM은 첫 호출 시 다음 명령으로 위치를 찾아 `$SCRIPTS` 환경변수로 사용한다:

```bash
SKILL_DIR=$(ls -d ~/.claude*/plugins/cache/account-partition/account-partition/*/skills/account-partition 2>/dev/null | sort -V | tail -1)
SCRIPTS="$SKILL_DIR/scripts"
```

이후 모든 헬퍼 호출은 `bash "$SCRIPTS/<name>.sh" ...` 형식.

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

## 보안 안내 (수시)

- `settings.json` 공유 시도가 발견되면(외부 환경) 매트릭스에 `⚠ 공유` 표시
- "MCP 토큰·외부 자격증명이 모든 계정에 노출되어 있습니다" 경고
- v1은 자동 분리 미지원. 수동 명령 안내:
  ```
  cp ~/.claude-shared/settings.json ~/.claude-<name>/settings.json
  rm ~/.claude-<name>/.. # symlink 제거 (계정마다)
  ```
