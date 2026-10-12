# 셸 통합 참조 (v0.5)

## 지원 셸과 대상 파일

| kind | OS | 자동 편집 대상 | 감지 조건 |
|---|---|---|---|
| `zsh` | macOS, Linux | `~/.zshrc` | `zsh` 실행 파일 또는 `~/.zshrc` 존재 |
| `bash` | macOS, Linux, Windows(Git Bash) | `~/.bashrc` | `bash` 실행 파일 존재 |
| `powershell` | Windows (5.1, 7), macOS·Linux (pwsh) | 각 에디션의 `$PROFILE.CurrentUserCurrentHost` | `powershell`/`pwsh` 존재. 경로는 `-NoProfile`로 질의 (OneDrive 문서 폴더 대응) |
| `cmd` | Windows | `~/bin/claude-<name>.cmd` + `~/bin/claude-<name>` (sh 래퍼) | 항상 (PATH 에 없으면 경고만) |
| fish 등 | — | 수동 안내 | — |

감지된 **모든** 대상에 같은 정의를 한 번에 기록한다. 셸마다 정의가 달라 실행 셸에 따라 다른 계정 구성이 뜨는 문제를 막기 위해서다. 확인: `bash "$SCRIPTS/ap.sh" targets`. `AP_TARGETS`(JSON 배열)로 감지 결과를 대체할 수 있다.

## 블록 형식

모든 블록은 시작/끝 마커로 감싼다. 생성 내용은 ASCII 전용이다.

```
# >>> account-partition: <name> >>>
...
# <<< account-partition: <name> <<<
```

예시와 설계 근거는 `docs/work/multi-os-token-partition/design.md` §5 참고. 요점:

- **env 누수 차단**: zsh/bash 는 `env -u CLAUDE_CONFIG_DIR -u CLAUDE_SECURESTORAGE_CONFIG_DIR ...`, PowerShell 은 `try/finally` 로 원래 값 복구, cmd 는 `setlocal`.
- **기본 계정(`~/.claude`)** 은 `CLAUDE_CONFIG_DIR` 를 설정하지 않고 지운다. macOS 키체인 항목 이름이 "변수 없음"과 "`~/.claude` 명시"에서 달라서, 명시하면 다시 로그인해야 한다.
- **Windows 경로**: 모든 셸이 `C:\Users\<me>\.claude-x` 라는 같은 문자열을 넘기도록 bash 블록도 `"$USERPROFILE\.claude-x"` 를 쓴다. 문자열이 다르면 데몬과 세션 목록이 갈라진다.
- **PowerShell**: `claude` 함수나 alias 가 있어도 `Get-Command claude -CommandType Application` 으로 실제 실행 파일을 부른다.

## v0.4 형식 호환

```
# account-partition: <name>
alias claude-<name>="CLAUDE_CONFIG_DIR=$HOME/.claude-<name> command claude"
```

remove 와 교체 대상으로 인식한다. 같은 이름을 다시 기록하면 새 형식으로 바뀐다.

## 외부 정의

마커 없는 `claude-*` 정의(alias, 함수, PowerShell 함수, `~/bin` 래퍼)는 list 에서 "외부" 로 보이고, `account-partition:adopt` 로만 수정한다. 해석 규칙은 adopt SKILL.md 참고.

## 파일 편집 규칙

- 줄 단위 편집은 바이트 수준으로 한다. UTF-8(BOM 유무 무관)과 CP949 모두 기존 내용이 보존된다.
- 줄바꿈은 기존 파일 스타일(CRLF/LF)을 따른다. 새 PowerShell 프로필은 UTF-8 BOM + CRLF.
- 모든 쓰기 전에 `<file>.bak.<YYYYMMDD-HHMMSS>-<pid>` 백업을 만든다. 롤백은 백업으로 복원한다. 백업은 자동 삭제되지 않는다.
