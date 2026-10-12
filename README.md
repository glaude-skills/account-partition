# account-partition

여러 Claude CLI OAuth 계정을 한 머신에서 셸 명령(예: `claude-work`, `claude-personal`)으로 분리하고, 계정 사이의 공유/격리 항목을 사용자가 선택할 수 있게 해주는 Claude Code plugin.

**상태**: v0.5 — 계정 추가 연동 / 조회 / 공유 항목 수정 / 로그인·로그아웃 / 연동 해제 + **멀티 OS**, **토큰만 분리 모드**, **기존 정의 가져오기(adopt)**
**플랫폼**: macOS, Linux, Windows(Git Bash 필요 — Claude Code Windows 요구사항과 같음) · python 3.8+
**셸**: zsh, bash, PowerShell(5.1/7), cmd 래퍼 — 감지된 모든 셸에 같은 정의를 동시에 기록. fish 등은 수동 안내

## 공유 정책

| 프리셋 | 공유 | 분리 |
|---|---|---|
| 기본 분리 | 플러그인·스킬·명령·서브에이전트 | 계정, 작업기록, 전역 설정, 시크릿 |
| **토큰만 분리** | 설정, 세션 목록(←← / `/resume`), 백그라운드 잡, 메모리, MCP, 플러그인 — 기준 계정 폴더 전체 | 로그인 토큰만 (`CLAUDE_SECURESTORAGE_CONFIG_DIR`) |
| 완전 격리 | 없음 | 전부 |
| 직접 선택 | 고른 항목 | 나머지 |

### 토큰만 분리 모드의 제약

- 세션 목록에서 **다른 계정이 띄운 세션에 참여하면, 그 세션을 띄운 계정의 토큰이 쓰입니다.** 참여(attach)는 이미 떠 있는 세션 프로세스에 붙기만 하고, 토큰은 프로세스가 뜰 때 정해지기 때문입니다. Claude Code 구조상 래퍼로 바꿀 수 없습니다. 계정을 바꾸려면 그 세션을 끝내고 `claude-<name> --resume <세션ID>` 로 다시 띄우세요.
- 화면에 표시되는 계정 이메일은 공유 파일(`.claude.json`)에 있어 마지막에 로그인한 계정 것으로 보일 수 있습니다. 실제 토큰은 분리돼 있습니다.
- `CLAUDE_SECURESTORAGE_CONFIG_DIR` 은 Claude Code 내부 변수입니다(2.1.292에서 확인). 공식 문서에 없어서 향후 버전에서 동작이 바뀔 수 있습니다.

## 설치

새 Claude Code 세션에서:

```
/plugin marketplace add glaude-skills/account-partition
/plugin install account-partition@account-partition
```

## 사용

메뉴에서 선택:

```
/account-partition
```

또는 액션 직접 호출:

```
/account-partition:add          # 계정 추가 연동
/account-partition:list         # 계정 조회 (공유/격리 매트릭스)
/account-partition:edit         # 공유 항목 수정
/account-partition:login        # OAuth 로그인 (v0.3+)
/account-partition:logout       # OAuth 로그아웃 (v0.3+)
/account-partition:unlink       # 연동 해제 — v0.4부터 자동화
/account-partition:adopt        # 손으로 만든 claude-* 정의 가져오기 (v0.5+)
```

## UX 원칙

- 자유 텍스트 입력은 **명령어 이름 단 1곳만** (예: `side` → `claude-side`)
- 그 외 모든 결정(메뉴·프리셋·항목 토글·yes/no 확인·충돌 해결)은 객관식 (방향키 + 엔터)

## 안전장치

- 모든 파괴적 변경은 **operation plan** 객체로 구성 → 미리보기·드라이런·실행·롤백이 모두 같은 plan에서
- **활성 세션 게이트** — 다른 Claude 프로세스가 같은 `CLAUDE_CONFIG_DIR`를 점유 중이면 변경 차단
- **계정별 lockfile** — 동시 호출 방지
- **격리 보존** — 충돌 사본은 즉시 삭제 아닌 `.account-partition-quarantine/`으로 이동
- **`settings.json` 격리 강제** — MCP 토큰 등 시크릿이 전 계정에 전파되지 않게
- **셸 파일 백업** — zsh/bash/PowerShell/cmd 파일을 고치기 전마다 `.bak.<ts>` 백업, 실패 시 롤백
- **env 누수 차단** — 생성된 명령은 부모 셸의 `CLAUDE_CONFIG_DIR`/`CLAUDE_SECURESTORAGE_CONFIG_DIR` 를 지우고 실행하며, PowerShell 은 실행 후 원래 값으로 복구
- **공유 config 보호** — 토큰만 분리 계정이 기대는 기준 계정은 unlink 거부, 토큰만 분리 계정 unlink 는 토큰 폴더만 정리
- **Windows junction 안전 삭제** — 링크만 걷어내고 공유 원본은 보존

## 검증 범위

- 단위 테스트: `bash skills/account-partition/tests/unit/run.sh` — Windows(Git Bash)와 Linux(Docker `python:3.12-slim`)에서 전부 통과. macOS 분기는 `AP_OS_OVERRIDE=macos` mock 으로만 확인 (v0.4.4 까지의 macOS 실기 검증 이후 macOS 실기 재검증은 아직 안 함)
- 실기: Windows 11 + PowerShell 5.1 + Git Bash 에서 adopt·토큰만 분리 확인, Linux 컨테이너에서 bash/zsh 실행 확인

## 디자인 / 구현 계획

- `docs/work/multi-os-token-partition/design.md` — v0.5 디자인 (멀티 OS, 토큰만 분리, adopt)
- `skills/account-partition/design.md` — v0.4 디자인 (리비전 3)
- `skills/account-partition/plan.md` — 구현 계획

## License

MIT
