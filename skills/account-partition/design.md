# account-partition — Claude CLI 계정 분할 스킬 디자인

작성일: 2026-05-26
Repo: `glaude-skills/account-partition` (또는 GGGGGANG/account-partition — org 생성 결과에 따라)
리비전: 3 (별도 plugin marketplace로 분리)

## 1. 한 줄 요약

여러 Claude 계정을 한 머신에서 alias로 분리해 호출하고, 각 계정 사이의 공유/격리 항목을 사용자가 선택할 수 있게 해 주는 스킬.

## 2. 동기

Claude Code는 `CLAUDE_CONFIG_DIR` 환경변수로 설정 디렉토리를 통째로 갈아끼울 수 있고, keychain의 OAuth 토큰도 그 경로 해시로 자동 격리한다. 이 메커니즘을 활용해 `claude-work`, `claude-personal` 같은 alias를 수동으로 구성한 사용자가 이미 있다(작성자 본인 셋업).

수동 구성은 다음을 매번 직접 처리해야 한다: 새 `CONFIG_DIR` 디렉토리 만들기, 공유할 항목을 별도 디렉토리(`~/.claude-shared`)로 빼고 심볼릭 링크 연결, `~/.zshrc`에 alias 한 줄 추가, 새 alias로 CLI 첫 실행 후 OAuth 로그인. 자동화 가치가 충분하고, 일반화하면 같은 패턴을 원하는 다른 사용자에게도 도움이 된다.

## 3. 목표 / 비목표

### v1 목표
- **계정 추가 연동** — 새 alias 생성 + 공유/격리 항목 선택 + 셸 통합 + 다음 안내
- **계정 조회** — 등록된 모든 alias의 공유/격리 매트릭스, 백업 현황, 외부 계정 인식
- **계정의 공유 항목 수정** — 기존 alias의 공유 ↔ 격리 토글, 충돌 해결
- 공유/격리 선택을 사용자가 객관식으로 결정
- 자유 텍스트 입력은 **명령어 이름 단 1곳만**, 나머지는 전부 방향키·엔터로 가능
- 파괴적 변경은 항상 미리보기 + 백업 + 단일 operation plan 기반 실행

### v1 비목표 (v2 또는 후속으로 이연)
- **계정 연동 해제(unlink)** — config dir 삭제, zshrc 라인 제거, keychain entry 정리. keychain 자동 삭제의 복구 불가성·service 이름 규칙 미검증 위험 때문에 v1에서 제외 (수동 명령 출력만 제공)
- **외부(스킬 외부에서 만든) alias의 자동 수정** — 손으로 만든 alias·함수형·다중 라인 케이스의 안전한 수정이 어려움. v1은 외부 alias를 **조회·인식까지만**, 수정은 사용자에게 수동 안내만
- macOS 외 OS 지원 (1차는 macOS + zsh. bash·fish는 수동 안내 fallback)
- 여러 머신 사이의 설정 동기화
- 임의 alias 그룹 사이의 부분 공유 (모든 alias가 단일 공유 풀 공유)
- Claude API key, custom endpoint 같은 비-OAuth 인증 관리

## 4. UX 원칙

| 입력 종류 | 처리 방식 |
|---|---|
| 명령어 이름 (예: `side`) | **자유 텍스트 입력** — 딱 1곳 |
| 메뉴 선택, 프리셋, 항목 토글, 셸 통합, 충돌 해결, 최종 확인 | **`AskUserQuestion`** (방향키 + 엔터) |

`yes/no` 자리도 모두 `AskUserQuestion`으로 통일.

## 5. 명령어 진입과 메인 메뉴

### Plugin 구조
`account-partition`은 **superpowers와 독립된 별도 marketplace plugin**. 별도 GitHub repo로 배포한다.

- repo: `glaude-skills/account-partition` (또는 본인 namespace fallback `GGGGGANG/account-partition`)
- marketplace name: `account-partition`
- plugin name: `account-partition`
- 단일 marketplace + 단일 plugin 구조 (확장 시 별도 plugin 추가 가능)

### 슬래시 명령
`/account-partition` — repo 루트 `commands/account-partition.md`로 정의. plugin install 후 cache 위치(`~/.claude*/plugins/cache/account-partition/account-partition/<version>/`)에서 발견됨.

**구현 전 검증 필요(§14 참조)**: plugin install이 정상이고, 실제로 `/account-partition`이 자동완성 + 호출 가능한지 확인.

### 사용자 설치 절차
```
/plugin marketplace add glaude-skills/account-partition
/plugin install account-partition@account-partition
```

(`gh:<org>/<repo>` 형식으로 GitHub repo 등록. 본인 namespace fallback이면 `GGGGGANG/account-partition`.)

### 스킬 디렉토리
plugin cache 안의 경로:
`~/.claude*/plugins/cache/account-partition/account-partition/<version>/skills/account-partition/`
- `SKILL.md` — AI 에이전트가 따를 흐름 (한국어)
- `design.md` — 이 문서

### 메인 메뉴 (`AskUserQuestion`)

```
무엇을 할까요?
● 계정 추가 연동
○ 계정 조회
○ 계정의 공유 항목 수정
○ 계정 연동 해제                 (v1 미지원 — 안내만)
```

v1에서 "계정 연동 해제" 선택 시 수동 명령 출력 + v2 예정 안내만 제공.

## 6. 액션별 흐름

### 6.1 계정 추가 연동

1. **명령어 이름 입력**(유일한 자유 입력) — 예: `side` → 호출 명령 `claude-side`
2. **검증**: `claude-<name>` 명령 존재 / `~/.claude-<name>/` 디렉토리 존재 / keychain entry 존재 여부 확인. 충돌 시 `AskUserQuestion`으로 "다른 이름으로 입력 / 기존 항목 인식해 (조회 또는 공유 항목 수정 흐름으로) 전환 / 취소"
3. **공유 정책 선택** — 프리셋 4종 중 1 (§7)
4. **(직접 선택 시) 항목별 토글** — `AskUserQuestion` multiSelect (§8)
5. **공유 보관소 위치** — 이 머신에서 처음 만들 때만 등장. 기본 `~/.claude-shared`, 또는 "다른 위치 지정" → 자유 입력
6. **셸 통합** — "자동 추가 + 백업" / "수동(명령만 출력)"
7. **활성 세션 게이트** (§11) — 다른 Claude 프로세스/daemon이 동일 `CLAUDE_CONFIG_DIR`를 점유 중인지 확인. 점유 중이면 진행 차단 + 안내. (신규 추가는 새 dir이라 충돌 가능성 낮지만, 공유 보관소를 처음 만드는 경로에서 `~/.claude` default와 겹치는 케이스를 위해 동일 게이트 적용)
8. **operation plan 생성 + 변경 미리보기** (§15) — 디스크 작업 목록, 백업 위치, alias 라인 미리보기. plan은 객체로 메모리에 보존, 미리보기·드라이런·실행·롤백 모두 같은 plan 사용
9. **최종 확인** — `AskUserQuestion`: "예 (실행) / 아니오 (취소) / 명령 출력만 (실제 변경 없이 plan을 셸 명령으로 출력)"
10. **plan 실행 + 결과 출력** — 다음 단계 안내(`source ~/.zshrc` → 새 alias 실행 → 첫 로그인)

### 6.2 계정 조회

다음을 출력 (읽기 전용, 디스크 변경 없음):

**연동된 계정 목록**
- 명령어 이름
- `CONFIG_DIR` 경로
- 계정 이메일 (`.claude.json`의 `oauthAccount.emailAddress`)
- 로그인 상태 (keychain entry 존재 여부)
- **등록 상태**: "스킬 관리" / "외부" / "⚠ 부분 등록 — <어느 부분이 빠졌는지>"

**공유/격리 매트릭스** — §8 분류표 기반. 셀 표기는 §8 범례.

**무시된 후보** — `~/.claude*` 글롭에 잡혔지만 계정 조건(§13)을 충족하지 못한 디렉토리 목록 (백업 tar, `removed` 잔존물, 비-claude 디렉토리 등).

**⚠ 시크릿 노출 경고** — 외부에서 만든 alias가 공유 보관소에 `settings.json`을 공유 중이면 "현재 전역 설정이 공유되어 MCP 토큰·외부 연동 자격증명이 모든 계정에 노출되어 있습니다. v1 스킬에서는 자동 분리 불가, 수동 명령으로 격리 권장" 안내.

**보관 중인 백업** — `~/.claude*.bak.*`, `~/.zshrc.bak.*`, `~/.claude*.removed.*.tar.gz`의 총 개수·용량. 정리는 사용자 수동.

### 6.3 계정의 공유 항목 수정

1. **계정 선택** — `AskUserQuestion` (스킬 관리 계정만 선택 가능. 외부 계정은 "외부 alias는 v1에서 수정 미지원, 수동 명령 출력?" 옵션)
2. **항목 토글 화면** — 현재 상태가 체크된 상태로 미리 표시. multiSelect (§8 토글 가능 항목만 노출)
3. **활성 세션 게이트** (§11)
4. **operation plan 생성 + 충돌 검사** (§10)
5. **충돌 해결 옵션** — 항목마다 `AskUserQuestion`. 공유 본 교체는 **전역 영향 경고 + 영향받는 alias 목록 표시**
6. **변경 미리보기 + 최종 확인** (§6.1 step 8~10과 동일 구조)

## 7. 프리셋

| 프리셋 | 공유 항목 | 사용 사례 |
|---|---|---|
| **기본 분리** ★ | 플러그인, 스킬, 슬래시 명령, 서브에이전트 | 도구는 한 벌, 계정·작업기록·전역 설정·시크릿 분리 |
| **완전 격리** | 없음 | 두 환경을 다른 머신처럼 다루고 싶을 때 |
| **거울 모드** | 위의 4종 + 글로벌 인스트럭션 | 환경 일치, 계정·시크릿만 분리 |
| **직접 선택** | 다음 화면에서 항목별 토글 | 세밀한 제어 |

★ = 추천 (메뉴 첫 번째)

**중요 변경(리비전 2)**: 모든 프리셋에서 **전역 설정(`settings.json`) 공유 제거**. 시크릿(MCP 토큰 등) 전파 위험 때문에 §8에서 격리 강제 항목으로 분류.

## 8. 항목 분류 및 라벨 매핑

### 토글 가능 (공유/격리 사용자 선택)

| 사용자 화면 라벨 | 실제 디스크 항목 | 설명 |
|---|---|---|
| 플러그인 | `plugins/` | 설치된 플러그인 본체 + 마켓플레이스 |
| 스킬 | `skills/` | 사용자 정의 스킬 |
| 슬래시 명령 | `commands/` | 사용자 정의 단축 명령 |
| 서브에이전트 | `agents/` | 사용자 정의 서브에이전트 정의 |
| 글로벌 인스트럭션 | `CLAUDE.md` | 계정 전반 인스트럭션 문서 |

**노출 규칙**: `~/.claude*` 어느 한 곳에라도 실제로 존재하는 항목만 토글 화면에 노출.

### 격리 강제 (공유 불가, 토글에 노출 안 됨)

| 사용자 화면 라벨 | 실제 디스크 항목 | 격리 사유 |
|---|---|---|
| **전역 설정** | `settings.json` | **MCP 토큰·외부 연동 자격증명 등 시크릿 노출 위험** (P1-8) |
| OAuth 계정 정보 | `.claude.json` | 계정별로 다름 |
| 프로젝트·메모리 | `projects/` | 작업 컨텍스트, 계정별로 다름 |
| 대화 기록·세션 | `sessions/`, `history.jsonl` | 계정별로 다름 |
| 로컬 권한 설정 | `settings.local.json` | 머신/환경별 |
| 데몬·잡 상태 | `daemon/`, `jobs/`, `debug/` | 활성 프로세스 상태 |
| 임시·캐시 | `paste-cache/`, `file-history/`, `shell-snapshots/`, `telemetry/`, `backups/` | 계정별 보관 |

### 자동 격리 (CLI가 처리, 사용자 제어 불필요)

| 라벨 | 메커니즘 |
|---|---|
| 자격증명 토큰 | keychain service 이름 = `Claude Code-credentials-<CONFIG_DIR 해시>` |

### 매트릭스 셀 범례

| 표시 | 의미 |
|---|---|
| `● 공유` | 공유 보관소와 심볼릭 연결되어 다른 계정과 같은 실체 사용 |
| `자체` | 이 계정만의 사본 보유 (격리 항목 또는 공유 옵션을 끈 항목) |
| `격리` | 격리 강제 항목 |
| `별도` | CLI가 자동 격리 |
| `─` | 해당 항목이 디스크에 없음 |
| `⚠ 공유` | 격리 강제 항목인데 외부에서 공유 중 — 시크릿 위험 (예: `settings.json`) |

## 9. 디스크 구조와 심볼릭 정책

### 단일 계정 디렉토리

`~/.claude-<name>/`
- 격리 항목은 디렉토리 안에 실체로 존재
- 공유 항목은 `~/.claude-shared/<항목>`을 가리키는 심볼릭 링크

### 공유 보관소

`~/.claude-shared/` (기본값, 사용자 변경 가능)
- 공유 대상 항목들의 실체 1개를 보관
- 각 계정 디렉토리에서 심볼릭 링크로 참조

### 항목 단위 vs 디렉토리 단위 링크

- 파일 항목(`CLAUDE.md`): 파일 단위 심볼릭
- 디렉토리 항목(`plugins/`, `skills/`, `commands/`, `agents/`): 디렉토리 단위 심볼릭

디렉토리 단위 링크의 부수효과: 디렉토리 내부 파일을 개별적으로 한쪽만 격리할 수는 없음. 1차 버전은 디렉토리 통째로 공유/격리만 지원.

### 원자적 파일 작업

모든 파일 이동·교체는 다음 절차로 (§11 안전장치 참조):
1. 임시 파일/디렉토리에 작업
2. `fsync` 또는 동등한 동기화
3. `rename` 원자 호출로 최종 위치 교체
4. 실패 시 임시 파일 청소

## 10. 충돌 해결 정책

공유로 전환할 때 이미 공유 보관소에 같은 항목이 있으면 `AskUserQuestion`으로 결정:

1. **공유 본 보존** (Recommended) — 계정 쪽 사본을 격리 보존 상태로 백업(즉시 삭제 아님), 심볼릭으로 교체
2. **사본으로 공유 본 덮어쓰기** — ⚠ **전역 영향 경고**: "이 작업은 현재 공유 본을 쓰는 모든 alias의 항목을 바꿉니다. 영향받는 alias: A, B, C. 백업: ..." 명시 후 진행. 기존 공유 본은 백업
3. **이 항목만 변경 취소** — 이 항목만 격리 유지

격리로 전환할 때(공유 → 격리):
- 심볼릭 링크를 끊고, 공유 본의 사본을 만들어 계정 디렉토리에 실체로 둠
- 공유 본 자체는 다른 alias가 쓰고 있을 수 있으므로 건드리지 않음
- 다른 alias가 더 이상 그 공유 본을 안 쓰면 공유 보관소에 그대로 남김 (자동 청소 안 함, 안전 우선)

### 격리 보존 (immediate-delete 금지)

리비전 2 변경: 충돌 해결에서 "백업 후 폐기"는 **즉시 삭제하지 않고** 격리 보존 디렉토리(`~/.claude-<name>/.account-partition-quarantine/<항목>.<ts>`)로 이동만. 별도 정리는 §11 백업 안내 영역에 표시.

## 11. 안전장치

### 활성 세션 게이트 (리비전 2 추가, P0-1 대응)

변경 작업 시작 전:
1. `CLAUDE_CONFIG_DIR` 별 활성 프로세스 검색 (`pgrep -f "claude"` + 환경변수 매칭)
2. `daemon.lock`, `daemon.status.json` 등 활성 daemon 마커 확인
3. 활성 발견 시 **변경 작업 차단** + "다른 Claude 세션이 실행 중입니다 (PID: ...). 종료 후 다시 시도하세요" 안내
4. 조회 작업은 영향 받지 않음

### 계정별 lockfile

변경 작업 진행 중 `<CONFIG_DIR>/.account-partition.lock` 생성. 다른 호출은 이 락이 풀릴 때까지 대기 또는 거부.

### 변경 미리보기
모든 파괴적 작업 전에 사람이 읽을 수 있는 형태로 작업 목록 출력. 사용자가 `AskUserQuestion`으로 명시 승인해야 진행.

### 백업
| 변경 종류 | 백업 위치 |
|---|---|
| `~/.zshrc` 수정 | `~/.zshrc.bak.<YYYYMMDD-HHMMSS>` |
| 공유 본 덮어쓰기 | `~/.claude-shared/<항목>.bak.<ts>` |
| 격리 보존 사본 | `~/.claude-<name>/.account-partition-quarantine/<항목>.<ts>` |

백업은 자동 삭제하지 않음. **계정 조회** 화면 하단에 "보관 중인 백업 (N개, 총 X MB)" 영역으로 안내하고, 별도 정리는 사용자 OS 도구로 직접 수행.

### Keychain 작업 가드 (리비전 2 추가, P0-3·P1-1 대응)

v1은 keychain 자동 삭제 안 함. 조회에서 entry 존재 여부만 확인:
1. `security find-generic-password -s "Claude Code-credentials-*"` 으로 entry 목록 수집
2. 각 entry의 service 이름에서 hash suffix 추출
3. 알려진 CONFIG_DIR 경로로 같은 hash가 산출되는지 교차 검증

**hash 산출 규칙은 구현 전 §14 검증 항목**. 검증 안 끝나면 keychain 매칭 표시도 "⚠ 추정"으로 표기.

v1의 keychain 관련 작업은 모두 **수동 명령 출력**: `security delete-generic-password -s "Claude Code-credentials-<hash>"` 같은 명령을 사용자가 직접 실행하도록 안내.

### 확인 게이트
- 디스크 변경 직전 1회 (변경 미리보기 후)
- 공유 본 덮어쓰기 시 전역 영향 경고 + 추가 확인 1회

### 롤백
실행 중 단계 실패 시 plan의 진행 단계만 역순으로 되돌리기:
- 심볼릭 제거
- 백업에서 파일 복구
- `~/.zshrc`에서 추가한 라인 제거
- keychain 항목은 v1에서 건드리지 않으므로 롤백 대상 아님

실패 지점과 롤백 결과를 출력. 사용자에게 수동 점검 권고.

## 12. 셸 통합

### 지원 셸
- 1차: zsh (`~/.zshrc`)
- 감지: `$SHELL` 환경변수 확인
- bash, fish, 그 외: v1은 자동 추가 미지원, 명령만 출력해 수동 안내

### Alias 라인 형식
```
# account-partition: <name>   ← 관리용 주석 (필수)
alias claude-<name>="CLAUDE_CONFIG_DIR=$HOME/.claude-<name> command claude"
```
- `command claude`: shell 함수보다 우선해서 실제 `claude` 바이너리 호출
- 경로는 `$HOME` 사용해 ~ 확장 문제 회피
- 관리용 주석으로 idempotency 보장

### 자동 추가 시
1. 셸 rc 파일 백업 (`.bak.<ts>`)
2. 파일 끝에 주석 + alias 두 줄 추가
3. 같은 `# account-partition: <name>` 주석으로 시작하는 블록이 이미 있으면 그 블록만 교체 (idempotent)

### 자동 편집 범위 제한 (리비전 2, P1-6 대응)
**자동 편집은 스킬이 만든 주석 블록만 대상**. 외부에서 손으로 만든 alias·함수형·다중 라인·source 분기는 자동 편집 안 함. 발견 결과는 조회에 표시하되 수정은 수동 명령 출력만.

### 수동 안내 시
복사 가능한 명령 1줄을 단독 코드블록으로 출력. 사용자가 직접 붙여넣어야 함을 명시.

## 13. 외부 계정 인식

스킬이 만들지 않은 alias도 **조회에서 인식**까지 지원. 자동 수정·삭제는 v1에서 안 함.

### 발견 로직

1. `~/.claude*` 패턴으로 디렉토리 스캔
2. 다음 디렉토리는 **항상 제외**:
   - 공유 보관소 (사용자가 지정한 경로, 기본 `~/.claude-shared`)
   - 비-디렉토리 항목 (`~/.claude.json` 등)
   - 백업 잔존물 (`.removed.*.tar.gz`, `.bak.*`)
   - 격리 보존 디렉토리(`.account-partition-quarantine`)
3. **계정 후보 조건 (리비전 2 강화, P2-9 대응)**: 다음 중 **1개 이상**을 충족한 경우만 계정으로 승격:
   - `.claude.json` 존재
   - 셸 rc 파일에 매칭되는 alias 라인 존재
   - keychain에 매칭 entry 존재 (hash 규칙 검증 후)
4. 미충족 후보는 "무시된 후보"로 별도 표시
5. `~/.claude/` (기본 default config)는 "계정명 없음 / 명령어 = `claude`"로 등록
6. `.claude.json`에서 `oauthAccount.emailAddress` 추출 (없으면 "—")
7. 셸 rc 파일에서 alias 라인 검색 (스킬이 만든 주석 블록 우선, 없으면 alias 본문 매칭)
8. keychain entry 매칭 (§11 keychain 가드)
9. 5~8의 정보를 디렉토리 경로 키로 매칭

### 부분 등록 표시

매칭 불일치 케이스는 조회 결과에 어느 부분이 빠졌는지 명시:
- "⚠ 부분 등록 — 디렉토리만 있음 (alias·keychain 없음)"
- "⚠ 부분 등록 — alias만 있음 (디렉토리 없음)"
- "⚠ 부분 등록 — 디렉토리·alias 있음 (keychain 없음 — 로그인 필요)"

## 14. 구현 전 검증 / 테스트

### 구현 전 검증 항목 (리비전 2 추가, P1-4·P1-5 대응)

이 항목들은 디자인의 핵심 전제. 구현 시작 전에 실제로 동작하는지 검증 필수:

1. **슬래시 명령 발견**: superpowers fork 루트 `commands/account-partition.md`를 만들고 `/account-partition`이 실제로 호출되는지. marketplace symlink 경유(`~/.claude-shared/plugins/marketplaces/superpowers-dev/`)에서도 노출되는지.
2. **Keychain service 이름 규칙**: 새 CONFIG_DIR로 첫 로그인했을 때 생기는 keychain entry의 service 이름 suffix를 캡처. CONFIG_DIR 경로의 어떤 해시 함수로 산출되는지 reverse engineer. 검증 안 끝나면 keychain 매칭은 "⚠ 추정"으로만.
3. **심볼릭 동작**: 디렉토리 단위 심볼릭이 Claude Code 정상 동작하는지(이미 사용자 셋업에서 검증되긴 했지만 새 항목 추가 시).

검증 결과는 별도 문서 `tests/preconditions.md`에 기록.

### 수동 검증 시나리오

자동 테스트가 어려운 영역이라 1차 버전은 수동 시나리오로 검증. `tests/manual.md`:
- Add: 새 alias 추가 → 디렉토리·심볼릭·zshrc·실제 실행 검증
- List: 매트릭스 정확성, 외부 alias 인식, 무시된 후보 분류
- Edit: 공유 ↔ 격리 전환, 충돌 해결 분기, 전역 영향 경고
- 활성 세션 게이트: 다른 Claude 세션이 떠있을 때 차단 동작
- 롤백: 실패 주입(권한 거부, 디스크 가득) 후 plan이 부분 진행 후 정상 롤백되는지

자동화 테스트 도입은 후속 과제.

## 15. Operation Plan 모델 (리비전 2 추가, P1-7 대응)

미리보기·드라이런·실행·롤백이 모두 같은 plan 객체에서 나오게 통합:

### Plan 구조

```
Plan {
  metadata: { action, alias_name, timestamp, ... }
  preconditions: [활성 세션 없음, 디렉토리 미존재, ...]
  operations: [
    { op: "create_dir", path, mode },
    { op: "create_symlink", src, dst, backup_if_exists },
    { op: "append_lines", file, lines, marker_comment },
    { op: "move_to_quarantine", src, dst },
    ...
  ]
  rollback: [operations의 역순 + 백업 위치]
}
```

### 사용 흐름

1. **plan 생성**: 액션 입력 + 현재 상태 스캔 → plan 객체
2. **변경 미리보기**: plan을 사람이 읽을 텍스트로 렌더 (이미지의 시뮬레이션 형태)
3. **사용자 선택**:
   - "예 (실행)" → 실행 엔진이 plan을 순차 처리, lockfile 보호, 단계별 상태 파일 기록
   - "아니오 (취소)" → plan 폐기
   - "명령 출력만" → plan operations를 셸 명령 시퀀스로 직렬화해 출력 (사용자가 직접 실행 가능한 형태)
4. **실행 직전 재검증**: precondition 재검사. 변했으면 plan 폐기하고 사용자에게 다시 확인 요청 (활성 세션이 새로 떴거나 디렉토리가 그 사이 만들어진 경우 등)
5. **실패 시 롤백**: plan의 rollback 섹션을 사용해 진행한 단계만 되돌림

### 상태 파일

부분 진행 중단 시 다음 위치에 plan 상태 기록:
- 공유 보관소가 이미 존재하면 `<공유보관소>/.account-partition-state.json`
- 첫 사용으로 아직 보관소가 없으면 `~/.account-partition-state.json` (작업 종료 시 보관소가 생기면 그쪽으로 이동)

다음 호출 때 상태 파일 감지하면 "이전 작업 미완료 감지됨, 정리할까?" 객관식 제공.

## 16. 오류 처리

### 검증 실패 (사전)
- 명령어 이름 충돌 → 다시 입력
- `~/.claude-shared/` 위치가 쓰기 불가 → 다른 위치 입력 객관식
- 셸 rc 파일 미존재 → 수동 안내로 전환
- 활성 Claude 세션 감지 → 변경 차단

### 실행 중 실패
- 권한 거부 → 명확한 에러 메시지 + 자동 롤백
- 심볼릭 생성 실패 (대상 경로 점유) → 충돌 해결 다이얼로그로 진입
- 디스크 가득 참 → 즉시 중단 + 롤백
- keychain 조작은 v1에서 안 함 (수동 명령 안내만)

### 부분 진행 후 종료
중간에 사용자가 인터럽트(Ctrl-C)하면 상태 파일(§15) 기반으로 다음 호출에서 "이전 작업 미완료 감지됨, 정리할까?" 객관식.

## 17. 보안·민감 정보

### 시크릿 전파 위험 (리비전 2 명시, P1-8 대응)

- **`settings.json`은 격리 강제 항목**. 기본 분리·거울 모드·직접 선택 모두에서 공유 불가
- 외부 alias가 이미 `settings.json`을 공유 중이면 조회에 "⚠ 시크릿 노출 — MCP 토큰·외부 자격증명이 모든 계정에 공유 중" 경고. v1은 자동 분리 미지원, 수동 안내만
- MCP 서버 설정·플러그인 marketplace 인증 등 시크릿이 들어갈 수 있는 다른 항목도 future-proof 검토 후속

### 파일 권한

- `.claude.json`, `settings.json`, `settings.local.json` 등은 권한 0600 유지
- 백업 파일도 0600
- `~/.zshrc`는 사용자 기본 설정 유지

### keychain
- 조회는 메타데이터만 (`security find-generic-password -s ...`), 토큰 값 자체는 출력 안 함
- v1에서 자동 삭제 안 함

## 18. 파일 구조 (구현 결과물)

별도 GitHub repo `glaude-skills/account-partition` (또는 fallback `GGGGGANG/account-partition`) 루트 기준:

```
.claude-plugin/
  marketplace.json            marketplace 메타데이터 (plugin 목록 정의)
  plugin.json                 plugin 메타데이터 (name, version, author)

commands/
  account-partition.md        슬래시 명령 정의 (스킬 invoke)

skills/account-partition/
  SKILL.md                    AI 에이전트가 따를 흐름 (한국어)
  design.md                   이 문서
  plan.md                     구현 계획
  references/
    item-mapping.md           항목 ↔ 라벨 매핑 상세
    shell-integration.md      셸별 통합 디테일
  scripts/                    bash 헬퍼 스크립트
  tests/
    preconditions.md          구현 전 검증 결과 (슬래시 명령·keychain hash)
    manual.md                 수동 검증 시나리오
    unit/                     bash assertion 기반 단위 테스트

README.md                     repo 소개 + 설치 안내
LICENSE                       MIT 또는 사용자 선호
.gitignore
```

### marketplace.json / plugin.json 핵심

`marketplace.json`:
```json
{
  "name": "account-partition",
  "description": "Plugin for managing multiple Claude CLI OAuth accounts via aliases",
  "owner": {"name": "gang00", "email": "<사용자 이메일>"},
  "plugins": [
    {"name": "account-partition", "description": "...", "version": "0.1.0", "source": "./"}
  ]
}
```

`plugin.json`:
```json
{
  "name": "account-partition",
  "description": "...",
  "version": "0.1.0",
  "author": {"name": "gang00"},
  "homepage": "https://github.com/glaude-skills/account-partition",
  "repository": "https://github.com/glaude-skills/account-partition",
  "license": "MIT"
}
```

(repo가 fallback이면 두 URL 모두 `GGGGGANG/account-partition`으로.)

### 슬래시 명령 발견 메커니즘 (중요)

CC는 `commands/<name>.md` 파일을 **install된 plugin의 cache 위치**에서 발견한다. 따라서:
1. repo에 commands/*.md commit 한다고 즉시 발견되지 않는다
2. 사용자가 `/plugin install <plugin>@<marketplace>`로 설치하면 cache가 생성되고, 그 안의 commands가 발견 대상이 된다
3. repo를 update해도 cache는 자동 갱신 안 됨 — 사용자가 `/plugin update <plugin>` 또는 reinstall 필요

이 메커니즘은 §14에서 실제 동작으로 검증한다.

## 19. v2 / 후속 과제

- **계정 연동 해제(unlink)** — keychain service 이름 규칙 검증 완료 후
- **외부 alias 자동 수정** — 손으로 만든 alias의 안전한 파싱·교체 방법론 정립 후
- **bash·fish 자동 통합**
- **Linux 지원** — libsecret/gnome-keyring 대안
- **Windows 지원** (별도 큰 작업)
- **공유 보관소 위치 변경 마이그레이션**
- **미사용 백업 자동 정리** (사용자 확인 후 일괄 삭제)
- **자동화 테스트 도입**
- **다중 머신 동기화** (별도 스킬)

## 20. 결정 근거 요약

| 결정 | 선택 | 이유 |
|---|---|---|
| 배치 위치 | 별도 plugin marketplace repo | superpowers와 독립, GitHub 공유 의도 (사용자 명시) |
| v1 동작 범위 | Add + List + 공유 항목 수정 | 안전성 우선, unlink·외부 자동 수정·keychain은 v2 |
| 호출 방식 | 슬래시 명령만 | 명시적 진입 명확 |
| 공유 구조 | 단일 풀 | 단순함, 멘탈모델 일치, YAGNI |
| UX 패턴 | 객관식 + 1곳 자유 입력 | 사용자 명시 요청, 인지 부담 최소 |
| 셸 통합 | 자동/수동 매번 선택, 자동은 주석 블록만 | 환경 다양성 + 안전 |
| 전역 설정 공유 | 격리 강제 | MCP 토큰·외부 자격증명 노출 위험 (P1-8) |
| 활성 세션 게이트 | 변경 작업 차단 | 동시성 충돌 방지 (P0-1) |
| 공유 본 교체 | 전역 영향 경고 + 격리 보존 | 즉시 삭제 금지, 다른 alias 영향 명시 (P0-2) |
| keychain 자동 삭제 | v1에서 미지원 | service 이름 규칙 미검증, 복구 불가 (P0-3) |
| 모든 변경 | 단일 operation plan | 미리보기·드라이런·실행·롤백 일관성 (P1-7) |
