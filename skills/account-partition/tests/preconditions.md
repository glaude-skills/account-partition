# 구현 전 검증 결과

## 검증 1: 슬래시 명령 발견 경로

검증일: 2026-05-26
검증자: gang (사용자)

### 사전 조건

- repo가 GitHub에 push되어 있고 `glaude-skills/account-partition` marketplace로 add됨
- `/plugin install account-partition@account-partition` 실행 완료
- `/reload-plugins`로 등록 활성화 필요

### 검증 절차

같은 Claude Code 세션에서:
1. `/plugin marketplace add glaude-skills/account-partition` (※ `gh:` prefix 없이)
2. `/plugin install account-partition@account-partition`
3. `/reload-plugins` ← 새 plugin install 후 필수
4. `/account-partition:account-partition` 실행 → SKILL.md placeholder 메시지 출력 확인

### 결과

**통과** ✓

- `/account-partition:account-partition` 노출: ✓ 자동완성 잡힘
- `/account-partition` 짧은 이름 노출: (별도 검증 안 함, namespace prefix로 호출 성공)
- SKILL.md placeholder 메시지 출력: ✓ 정상 출력
- 첫 install 시 cache 경로: `~/.claude-work/plugins/marketplaces/glaude-skills-account-partition--plugin-install-account-partition/` (사용자 환경이 claude-work alias라 `.claude-work` 하위)
- `/reload-plugins` 후: 3 plugins · 11 skills · 8 agents · 4 hooks · 0 MCP · 0 LSP

### 메모

- **첫 시도 실패**: 사용자가 `gh:glaude-skills/account-partition`로 입력해 "Invalid marketplace source format" 에러. CC의 marketplace add는 `gh:` prefix를 거부하고 `owner/repo` 형식만 받음. 디자인 문서·README의 안내를 모두 수정 후 재시도하여 성공.
- **SSH key 미설정 영향**: marketplace add가 `git@github.com:...` SSH URL로 clone 시도하다 "Permission denied (publickey)"로 실패하는 케이스가 한 번 있었음. 사용자 ssh-agent에 키가 안 올라간 상태가 원인 추정. 그러나 `owner/repo` 형식으로 다시 시도하니 CC가 HTTPS로 fallback해 성공.
- **install 후 `/reload-plugins` 필수**: install만으로는 슬래시 명령·스킬 발견 안 됨. CC의 plugin 시스템은 lazy load 아니고 reload 필요.
- **slash command 발견 경로**: fork 루트의 `commands/*.md`가 아니라 **install된 plugin의 cache** 위치에서 발견. 디자인 §5/§18 가설 검증 완료.

---

## 검증 2: Keychain service 이름 hash 규칙

검증일: 2026-05-26
검증자: claude (자동 시도) + gang (확인)

### 결과: **알고리즘 미확인 → fallback 적용**

### 시도한 알고리즘 (모두 매칭 실패)

기준 매핑:
- `/Users/gang/.claude-work` → `64ad4bd9`
- `/Users/gang/.claude-personal` → `c28821e0`

시도한 조합 (해시 함수 × 입력 정규화 변형):
- 해시: SHA-256(first/mid/last 8), SHA-1(first/last 8), MD5(first/last 8), CRC32, Adler32
- 정규화: raw, trailing-slash, ~ 확장, home-relative, name-only, `CLAUDE_CONFIG_DIR=` prefix, `file://` URI, realpath
- 총 **63개 조합 모두 미스매치**. CC binary는 Mach-O 64-bit (Node.js 컴파일). 내부에 비표준 해시 또는 솔트·키 사용 추정.

CC binary `strings` 분석에서도 hash 함수 직접 hint 미발견 (소스가 minified·shipped).

### Fallback 정책 (디자인 §11 적용)

v1에서 **keychain entry → config dir 매핑은 시도하지 않음**. 대신:

1. **로그인 상태 판별은 `.claude.json`의 `oauthAccount.emailAddress` 유무로**:
   - 값 있음 → "✓ 로그인됨" + 이메일 표시
   - 빈 값/필드 없음 → "—" (로그인 안 됨 또는 첫 실행 전)
2. **keychain entry 자체는 정보 표시 안 함** (어떤 entry가 어느 계정인지 알 수 없으므로 잘못된 매칭 방지)
3. **v2에서 hash 알고리즘 reverse engineer 재시도** — Phase 후속 과제

이 방식이 keychain 매칭보다 더 신뢰성 높음:
- `.claude.json`은 CC가 직접 관리하므로 stale 가능성 낮음
- keychain entry는 사용자가 `/logout` 후 stale 상태로 남을 수도

### 메모

- macOS 24.3.0 + CC version: Claude Code 2.x (claude-code-cli)
- 해시 알고리즘 미확인은 v1 진행 차단 요소 아님 (디자인의 fallback이 이미 정상 동작 경로)

## 검증 3: Windows 전제 (v0.5, 디자인 §21.3)

2026-10-07, Windows 11 Home 10.0.26200 + Claude Code 2.1.292 + Git Bash 5.2.26 (MINGW64) + Windows PowerShell 5.1. 개발자 모드 꺼짐(레지스트리 `AppModelUnlock\AllowDevelopmentWithoutDevLicense` 없음).

| # | 전제 | 결과 | 확인 방법 |
|---|---|---|---|
| 1 | CC가 Bash 블록을 Git Bash로 실행 | **성립** | Bash 도구 안에서 `uname -s` = `MINGW64_NT-10.0-26200`, `$MSYSTEM` = `MINGW64` |
| 2 | Git Bash `ln -s`가 진짜 링크를 만든다 | **불성립** | 기본(`MSYS=disable_pcon`)에서는 오류 없이 **복사본**이 생긴다. `dir /AL`에 안 잡히고 원본 수정이 반영되지 않는다. `MSYS=winsymlinks:nativestrict`로 강제하면 `Operation not permitted` |
| 3 | junction을 권한 없이 만든다 | **성립** | `cmd //c "mklink /J <link> <target>"` 성공. `fsutil reparsepoint query` 태그 `0xa0000003`. 양쪽 수정이 서로 보인다 |
| 4 | `claude auth status`가 JSON | **성립** | 키: `analyticsDisabled`, `apiProvider`, `authMethod`, `configDirectory`, `email`, `loggedIn`, `orgId`, `orgName`, `projectsDirectory`, `subscriptionType` |

추가로 본 것:

- **파일 하드링크**(`mklink /H`)는 권한 없이 된다. 다만 편집기가 새 파일을 쓰고 이름을 바꾸는 방식으로 저장하면 링크가 조용히 끊긴다. 그래서 `CLAUDE.md` 공유 수단으로 쓰지 않기로 했다(디자인 §21.2).
- **이미 손으로 나눈 계정이 있다.** PowerShell 프로필의 `claude-work`, `claude-dami` 함수가 `CLAUDE_CONFIG_DIR`을 바꿔 `claude`를 부른다. 두 계정 모두 `skills`, `plugins`, `commands`를 `~/.claude`로 향하는 junction으로 공유하고 `settings.json`은 따로 둔다.
- **그 함수들은 환경변수를 되돌리지 않는다.** `claude-work`를 한 번 실행한 PowerShell 창에서는 이후 그냥 `claude`를 쳐도 work 계정으로 뜬다.
- **plugins 공유와 settings 격리가 어긋나는 사고를 실제로 겪었다.** 마켓플레이스 저장소를 옮긴 뒤 `plugins/known_marketplaces.json`(공유)은 새 주소가 됐는데 `settings.json`의 `extraKnownMarketplaces`(계정별)는 옛 주소로 남아, 그 계정에서 플러그인이 "added but ignored"로 꺼졌다.

적대적 리뷰 후 추가로 재현한 것 (디자인 §21.8):

| 확인 | 결과 |
|---|---|
| 실행 엔진의 `python3` | WindowsApps 경로의 네이티브 Python 3.12, `sys.platform == "win32"`. `os.path.abspath('/c/Users/gang')` = `C:\c\Users\gang` |
| Python의 junction 판정 | `os.path.islink` = False, `os.path.isjunction` = True. bash의 `[ -L ]`, `[ -h ]`는 true |
| Python `open()` 기본 인코딩 | cp949 |
| MSYS `rm -rf <dir>` (안에 junction) | 대상 보존 |
| MSYS `rm -rf <junction>` | junction만 제거, 대상 보존 |
| MSYS `rm -rf <junction>/` (끝에 `/`) | **대상 내용 전부 삭제** |
| PowerShell ExecutionPolicy | CurrentUser = RemoteSigned (이 PC). 클라이언트 기본값 Restricted면 프로필이 로드되지 않는다 |
