# 항목 매핑 참조

이 문서는 account-partition 스킬이 다루는 항목별 사용자 화면 라벨과 실제 디스크 처리를 정리합니다.

## 토글 가능 항목 (공유/격리 사용자 선택)

| 사용자 화면 라벨 | 실제 디스크 경로 | 유형 | 설명 |
|---|---|---|---|
| 플러그인 | `plugins/` | 디렉토리 | 설치된 플러그인 본체 + 마켓플레이스 |
| 스킬 | `skills/` | 디렉토리 | 사용자 정의 스킬 |
| 슬래시 명령 | `commands/` | 디렉토리 | 사용자 정의 단축 명령 |
| 서브에이전트 | `agents/` | 디렉토리 | 사용자 정의 서브에이전트 정의 |
| 글로벌 인스트럭션 | `CLAUDE.md` | 파일 | 계정 전반 인스트럭션 문서 |

**공유 시 동작**: `~/.claude-<name>/<item>` 위치에 `~/.claude-shared/<item>`을 가리키는 심볼릭 링크 생성.

**격리 시 동작**: 디렉토리·파일을 계정 디렉토리 안에 실체로 보관.

**노출 규칙**: `~/.claude*` 어느 한 계정에라도 디스크에 존재하는 항목만 토글 화면에 노출.

## 격리 강제 항목 (공유 불가)

| 사용자 화면 라벨 | 실제 디스크 경로 | 격리 사유 |
|---|---|---|
| 전역 설정 | `settings.json` | **MCP 토큰·외부 연동 자격증명 노출 위험** |
| OAuth 계정 정보 | `.claude.json` | 계정별로 본질적으로 다름 |
| 프로젝트·메모리 | `projects/` | 작업 컨텍스트, 계정별 다름 |
| 대화 기록·세션 | `sessions/`, `history.jsonl` | 계정별 |
| 로컬 권한 설정 | `settings.local.json` | 머신/환경별 |
| 데몬·잡 상태 | `daemon/`, `jobs/`, `debug/` | 활성 프로세스 상태 |
| 임시·캐시 | `paste-cache/`, `file-history/`, `shell-snapshots/`, `telemetry/`, `backups/` | 계정별 |

## 자동 격리 항목 (CLI가 처리)

| 라벨 | 메커니즘 |
|---|---|
| 자격증명 토큰 | 저장 폴더 = `CLAUDE_SECURESTORAGE_CONFIG_DIR` (없으면 config 폴더). Windows·Linux 는 그 폴더의 `.credentials.json`, macOS 는 키체인 service `Claude Code-credentials-<sha256(폴더 경로 문자열) 앞 8자리>` (변수가 모두 없으면 접미사 없음). Claude Code 2.1.292 바이너리에서 확인 |

## 토큰만 분리 모드 (v0.5)

config 폴더를 기준 계정과 통째로 공유하고 토큰 저장 폴더만 `~/.claude-<name>` 으로 분리한다. 위 표의 "격리 강제 항목"(설정, `.claude.json`, 프로젝트·메모리, 세션, 데몬·잡)까지 모두 공유되므로, 세션 목록(←← / `/resume`)과 백그라운드 잡이 두 계정에 똑같이 보인다.

제약: 세션 프로세스의 토큰은 그 세션을 **띄운** 계정의 것으로 고정된다. 다른 계정에서 띄운 세션에 참여(attach)하면 그 계정 토큰이 소모된다. 멈춘 백그라운드 세션을 `claude attach` 나 `claude --bg --resume <id>`(플래그 없이)로 깨워도 `jobs/<id>/state.json` 의 `providerEnv` 가 다시 쓰인다. `--bg --resume` 에 플래그를 붙이면 새 id 의 복사본이 된다 (2.1.311 실측).

v0.5.2 래퍼는 `attach` 를 `~/.claude-shared/ap_attach.py` 로 넘긴다. `providerEnv` 의 토큰 폴더와 지금 계정 토큰 폴더가 다르면 `claude stop <id>` 뒤 세션 `cwd` 에서 `claude --resume <sessionId> <respawnFlags>` 를 포그라운드로 연다. 같은 transcript 에 이어 기록된다 (2.1.311 실측). Claude Code 화면 안의 ←← 참여는 래퍼를 거치지 않는다.

### MCP 의 공유 범위

| 종류 | 저장 위치 | 토큰만 분리에서 |
|---|---|---|
| 로컬 MCP 서버 정의 (`claude mcp add`) | `.claude.json` / `settings.json` | 공유 |
| claude.ai 커넥터 목록 | claude.ai 서버 (`GET /v1/mcp_servers`, 조직·사용자 기준) | 같은 조직이면 같음. 로컬에서 바꿀 수 없음 |
| claude.ai 커넥터 로그인 (어느 외부 계정에 붙었나) | claude.ai 서버, 사용자별 | 공유 불가. 계정마다 claude.ai 에서 다시 연결 |

`claude mcp list` 는 로컬 서버만 보여 주고 claude.ai 커넥터는 나오지 않는다 (2.1.311 실측).

### 기준 계정을 토큰만 분리로 바꾸기

기준 계정(`~/.claude`, standard)에 이름을 붙여 쓰다가 기본 `claude` 와 따로 관리해야 할 때가 있다. edit 은 모드 변경을 지원하지 않으므로 registry 항목을 `mode: token-only`, `token_dir: ~/.claude-<name>` 으로 바꾸고 `_write_ops_for` + `apply_op` 로 셸 정의를 다시 쓴다(`registry_save` 로 기록).

토큰은 `~/.claude/.credentials.json` 을 복사하지 말고 `/account-partition:login <name>` 으로 새로 로그인한다. 복사하면 두 폴더가 같은 refresh 토큰을 갖고, 한쪽이 갱신하는 순간 다른 쪽이 끊긴다(v0.5.1 기록과 같은 원인).

## 매트릭스 셀 범례

| 표시 | 의미 |
|---|---|
| `● 공유` | 공유 보관소(`~/.claude-shared/<item>`)와 심볼릭 링크 |
| `자체` | 이 계정만의 사본 보유 |
| `격리` | 격리 강제 항목 (공유 불가) |
| `⚠ 공유` | 격리 강제 항목인데 외부에서 공유 중 — 시크릿 노출 위험 |
| `─` | 해당 항목이 디스크에 없음 |
