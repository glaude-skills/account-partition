---
name: unlink
description: "Claude CLI 계정 연동 해제 — v1 미지원, 수동 명령 안내만."
---

# 계정 연동 해제 (v1 미지원)

## 호출 시 announce

"account-partition 스킬로 계정 연동 해제 안내를 진행할게."

## Scripts 위치 찾기

이 스킬의 헬퍼 스크립트는 plugin cache 안에 있다. LLM은 첫 호출 시 다음 명령으로 위치를 찾아 `$SCRIPTS` 환경변수로 사용한다:

```bash
SKILL_DIR=$(ls -d ~/.claude*/plugins/cache/account-partition/account-partition/*/skills/account-partition 2>/dev/null | sort -V | tail -1)
SCRIPTS="$SKILL_DIR/scripts"
```

## 흐름

호출 시 다음 안내만 출력:

```
계정 연동 해제는 v1에서 자동화하지 않습니다. 다음을 수동으로 진행하세요:

1) ~/.zshrc 에서 alias 라인 제거:
   (스킬이 만든 라인은 marker '# account-partition: <name>' 블록을 sed로 제거)

   bash <plugin cache>/skills/account-partition/scripts/shell-rc.sh remove ~/.zshrc <name>

2) 계정 디렉토리 백업 후 제거:
   tar czf ~/.claude-<name>.removed.$(date +%Y%m%d-%H%M%S).tar.gz -C ~ .claude-<name>
   rm -rf ~/.claude-<name>

3) (선택) keychain 항목 수동 제거:
   security delete-generic-password -s "Claude Code-credentials-<hash>"
   (hash 알고리즘 미확인 — keychain 항목 식별은 사용자 직접)

v2에서 자동화 예정.
```

`<plugin cache>` 위치는 `$SCRIPTS` 변수의 상위 디렉토리를 참고해 안내한다:
```bash
echo "plugin cache 경로: $(dirname "$SCRIPTS")"
```
