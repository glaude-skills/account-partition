# 셸 통합 참조

## 지원 셸

| 셸 | v1 지원 | 자동 편집 대상 파일 |
|---|---|---|
| zsh | ✓ | `~/.zshrc` |
| bash | (수동 안내만) | `~/.bashrc` 또는 `~/.bash_profile` |
| fish | (수동 안내만) | `~/.config/fish/config.fish` |
| 그 외 | (수동 안내만) | — |

자동 편집은 zsh + `~/.zshrc` 한정. 그 외는 사용자가 명령 라인을 복사·붙여넣기.

## Alias 라인 형식

```
# account-partition: <name>
alias claude-<name>="CLAUDE_CONFIG_DIR=$HOME/.claude-<name> command claude"
```

- 관리 주석(`# account-partition: <name>`) 필수 — 스킬이 자동 편집할 때 식별자.
- `command claude` — 셸 함수보다 우선해서 실제 `claude` 바이너리 호출.
- `$HOME` 사용 — `~` 확장 문제 회피.

## Idempotency

같은 `<name>`으로 add 호출 시:
1. 기존 marker 블록(`# account-partition: <name>` 및 다음 라인) 제거
2. 새 marker 블록 추가
3. 라인 수 동일 유지

## 외부 alias 처리

스킬이 만들지 않은(주석 없는) `claude-*` alias는:
- 조회(`list` subcommand)에서 `:external` 라벨로 표시됨
- 자동 수정·삭제 **안 함**
- 사용자가 직접 편집해야 함

이유: 손으로 만든 alias·함수·다중 라인·source 분기 등의 모서리 케이스가 안전한 자동 처리를 어렵게 함. v2 후속 과제.

## 자동 편집 시 백업

`~/.zshrc.bak.<YYYYMMDD-HHMMSS>-<pid>` 형식으로 백업 생성. 백업은 자동 삭제되지 않음.
