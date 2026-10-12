# 멀티 OS 지원 + 토큰만 분리 모드 + adopt (v0.5.0)

작성일: 2026-10-12 · 상태: 사용자 결정 반영 완료, 구현 진행

## 1. 배경

Windows 사용자가 PowerShell 프로필에 손으로 `claude-dami` 함수를 만들어 "설정·세션·백그라운드 잡은 `claude-work`와 공유하고 로그인 토큰만 분리"하는 구성을 썼다. 이때 두 가지 문제가 드러났다.

1. **세션 목록(←← / `/resume`)에서 기존 세션에 참여하면 토큰이 세션을 띄운 계정 기준으로 소모된다.** 데몬이 세션 프로세스를 띄울 때 그 시점 클라이언트의 env(`CLAUDE_SECURESTORAGE_CONFIG_DIR`)를 넘기고, 참여(attach)는 이미 떠 있는 프로세스의 PTY에 붙기만 하기 때문이다. Claude Code 구조상 래퍼로는 바꿀 수 없다(훅 이벤트에 attach 없음, `reattachEnv`는 launch 요청 필드). 사용자는 이 제약을 수용하기로 결정했다.
2. **같은 이름의 정의가 셸마다 달랐다.** PowerShell 함수는 토큰만 분리, `~/bin/claude-dami`(bash)와 `.cmd`는 완전 분리였다. 또 PowerShell 함수는 `$env:`를 복구하지 않아 같은 창의 이후 `claude` 실행에 계정이 새어 들어갔다.

이 플러그인(v0.4.4)은 macOS + zsh 전용이었고, 이 구성을 지원하지 않았다.

## 2. 사용자 결정 (2026-10-12)

| # | 질문 | 결정 |
|---|---|---|
| 1 | 세션 목록 공유 vs 완전 분리 | **공유 유지.** 참여 시 토큰은 띄운 계정 기준이라는 제약을 문서화 |
| 2 | 스킬 업데이트 범위 | **기능 구현까지** |
| 3 | 플랫폼 | **거의 모든 OS** (macOS, Linux, Windows) |
| 4 | 자동 기록 셸 | **zsh + bash + PowerShell + cmd 래퍼** (fish는 수동 안내) |
| 5 | 여러 셸 등록 방식 | **감지된 셸 전부에 동시 기록** (불일치 원천 차단) |
| 6 | 손으로 만든 외부 정의 | **adopt 기능 추가** |
| 7 | 헬퍼 언어 | **bash + python3 유지 + 플랫폼 계층** (접근안 A) |

## 3. 핵심 사실 (Claude Code 2.1.292 바이너리에서 확인)

```js
function nw(){ let e=process.env.CLAUDE_SECURESTORAGE_CONFIG_DIR;
  if(e!==void 0) return (e||join(homedir(),".claude")).normalize("NFC"); return we() }   // 토큰 파일 폴더
function jJ(e=""){ let n=process.env.CLAUDE_SECURESTORAGE_CONFIG_DIR,
  t = n!==void 0 ? !n : !process.env.CLAUDE_CONFIG_DIR,
  r = n!==void 0 ? n.normalize("NFC") : we(),
  c = t ? "" : `-${sha256(r).hex.substring(0,8)}`;
  return `Claude Code${OAUTH_FILE_SUFFIX}${e}${c}` }                                       // macOS 키체인 서비스 이름
```

- Windows/Linux: `.credentials.json`을 `CLAUDE_SECURESTORAGE_CONFIG_DIR`(없으면 config 폴더)에 저장한다.
- macOS: 키체인 서비스 이름이 이 폴더 경로 문자열의 sha256 앞 8자리로 정해진다. 따라서 **경로 문자열이 셸마다 정확히 같아야** 같은 토큰을 본다.
- `CLAUDE_CONFIG_DIR`가 **없을 때**와 `~/.claude`로 **명시했을 때** 키체인 이름이 다르다(접미사 유무). 기본 계정(`~/.claude`)은 변수를 설정하지 말고 지워야 기존 로그인이 유지된다.
- SDK와 데몬은 자식 프로세스에 이 변수를 일관되게 전달한다. 문서화되지 않았지만 내부적으로 지원되는 변수다.

## 4. 계정 모델

계정 정의 = `name` + `mode` + `config_dir` + `token_dir` + `extra_env`.

| 모드 | `CLAUDE_CONFIG_DIR` | `CLAUDE_SECURESTORAGE_CONFIG_DIR` | 링크 |
|---|---|---|---|
| `standard` (기존 프리셋 4종) | `~/.claude-<name>` (기본 계정이면 unset) | unset | 프리셋대로 공유 보관소 링크 |
| `token-only` (신규) | 기준 계정의 폴더 (기본 계정이면 unset) | `~/.claude-<name>` | 없음 |

- 단일 원본은 `<shared_pool>/accounts.json`(기본 `~/.claude-shared/accounts.json`)이다. 셸 파일은 이 원본으로부터 생성되는 결과물이다.
- 경로는 홈 기준 상대형(`~/.claude-work`)으로 저장하고, 셸마다 그 셸의 홈 표현으로 렌더링한다.
- `extra_env`는 adopt 시 보존한 사용자 변수(예: `CLAUDE_PROFILE=work`)다.

```json
{
  "version": 1,
  "accounts": {
    "dami": {
      "mode": "token-only",
      "config_dir": "~/.claude-work",
      "token_dir": "~/.claude-dami",
      "extra_env": {"CLAUDE_PROFILE": "dami"},
      "targets": [{"kind": "powershell", "path": "C:/Users/me/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1"}],
      "updated_at": "2026-10-12T10:00:00"
    }
  }
}
```

## 5. 셸 백엔드

### 5.1 대상 감지 (`aplib.detect_targets`)

| kind | 조건 | 파일 |
|---|---|---|
| `zsh` | `zsh` 실행 파일 존재 또는 `~/.zshrc` 존재 | `~/.zshrc` |
| `bash` | `bash` 실행 파일 존재 | `~/.bashrc` (macOS에서 `~/.bash_profile`이 `.bashrc`를 불러오지 않으면 경고) |
| `powershell` | `powershell`/`pwsh` 각각 존재 | 각 에디션에 `-NoProfile -Command $PROFILE.CurrentUserCurrentHost`로 질의한 실제 경로 (OneDrive 리다이렉트 대응) |
| `cmd` | Windows | `~/bin/claude-<name>.cmd` + `~/bin/claude-<name>` (sh 래퍼, Git Bash·IDE·스크립트용) |

테스트와 특수 환경용으로 `AP_TARGETS`(JSON 배열) 환경변수가 감지 결과를 대체한다. `~/bin`이 PATH에 없으면 자동 수정하지 않고 안내만 한다.

### 5.2 블록 형식

모든 블록은 `# >>> account-partition: <name> >>>` ~ `# <<< account-partition: <name> <<<` 마커로 감싼다. 생성되는 블록 내용은 **ASCII 전용**이다(PowerShell 5.1 인코딩 문제 회피). 기존 v0.4 형식(`# account-partition: <name>` + 다음 줄 alias)도 인식하고, 갱신 시 새 형식으로 바꾼다.

**posix (zsh/bash)**: alias 대신 함수. `env -u`로 두 변수를 지운 뒤 필요한 것만 다시 설정해서 부모 셸의 값이 새지 않게 한다.

```bash
# >>> account-partition: dami >>>
unalias claude-dami 2>/dev/null || true
claude-dami() { env -u CLAUDE_CONFIG_DIR -u CLAUDE_SECURESTORAGE_CONFIG_DIR CLAUDE_CONFIG_DIR="$HOME/.claude-work" CLAUDE_SECURESTORAGE_CONFIG_DIR="$HOME/.claude-dami" claude "$@"; }
# <<< account-partition: dami <<<
```

Windows(Git Bash)에서는 경로를 `"$USERPROFILE\.claude-work"` 형태로 렌더링한다. `$HOME`(`/c/Users/...`)을 그대로 넘기면 네이티브 `claude.exe`가 다른 경로 문자열을 받아 데몬과 세션 목록이 갈라진다. 모든 셸이 `C:\Users\<me>\.claude-work`라는 같은 문자열을 넘기는 것이 핵심이다.

**powershell**: `try/finally`로 원래 값을 복구하고, `claude` 함수나 alias가 있어도 실제 실행 파일을 호출한다.

```powershell
# >>> account-partition: dami >>>
function claude-dami {
  $apKeys = @('CLAUDE_CONFIG_DIR', 'CLAUDE_SECURESTORAGE_CONFIG_DIR')
  $apSaved = @{}
  foreach ($k in $apKeys) { $apSaved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process') }
  try {
    [Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', (Join-Path $HOME '.claude-work'), 'Process')
    [Environment]::SetEnvironmentVariable('CLAUDE_SECURESTORAGE_CONFIG_DIR', (Join-Path $HOME '.claude-dami'), 'Process')
    $apExe = Get-Command claude -CommandType Application -ErrorAction Stop | Select-Object -First 1
    & $apExe @args
  } finally {
    foreach ($k in $apKeys) { [Environment]::SetEnvironmentVariable($k, $apSaved[$k], 'Process') }
  }
}
# <<< account-partition: dami <<<
```

**cmd 래퍼** (CRLF, `setlocal`로 누수 차단):

```bat
@echo off
rem >>> account-partition: dami (managed - do not edit) >>>
setlocal
set "CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-work"
set "CLAUDE_SECURESTORAGE_CONFIG_DIR=%USERPROFILE%\.claude-dami"
claude %*
```

### 5.3 파일 편집 규칙

- 줄 단위 편집은 **바이트 수준**으로 한다. 기존 파일이 UTF-8(BOM 유무 무관)이든 CP949든 깨지지 않는다. 마커와 블록이 ASCII라 바이트 정규식으로 충분하다.
- 줄바꿈은 파일의 기존 스타일(CRLF/LF)을 따른다. 새 PowerShell 프로필은 UTF-8 BOM + CRLF로 만든다.
- 모든 쓰기 전에 `<file>.bak.<ts>` 백업을 만들고 롤백은 백업으로 복원한다.

## 6. adopt (외부 정의 가져오기)

### 6.1 인식 패턴

| 위치 | 인식 |
|---|---|
| zsh/bash rc | `alias claude-x="VAR=v ... [command] claude"`, 한 줄 함수 `claude-x() { [env -u ..] VAR=v ... [command] claude "$@"; }`, 여러 줄 함수 본문의 `export VAR=v` / `unset VAR` / `[exec\|command] claude "$@"` |
| PowerShell | `function claude-x { ... }` 본문의 `$env:VAR = '...'`, `Remove-Item Env:VAR ...`, `[&] claude @args` |
| cmd 래퍼 | `@echo off`, `rem`, `setlocal`, `set [\"]VAR=v[\"]`, `[call] claude %*` |
| sh 래퍼 | `#!`, 주석, `[export] VAR=v`, `unset`, `[exec] claude "$@"` |

그 외 문장이 하나라도 섞이면 **해석 불가**로 표시하고 손대지 않는다. 값의 `$HOME`, `${HOME}`, `~`, `$USERPROFILE`, `%USERPROFILE%`, `$env:USERPROFILE`, `(Join-Path $HOME '...')`은 홈 상대 경로로 정규화한다.

### 6.2 통일과 적용

- 정의마다 `(config_dir, token_dir, extra_env)` 서명을 만든다. 서명이 여러 개면 사용자에게 고르게 한다(SKILL.md의 객관식).
- plan: 외부 정의 제거(`remove_external`, 바로 위에 붙은 주석 줄 포함) → 모든 대상에 관리 블록 기록(`write_block`/`write_file`) → `registry_put`.
- 기존 래퍼 파일은 백업 후 관리 래퍼로 덮어쓴다.
- adopt는 config 폴더를 건드리지 않으므로 활성 세션 게이트를 적용하지 않는다.

## 7. 토큰만 분리 모드 (add)

- add Step 2에 프리셋 "토큰만 분리"를 추가한다. 고르면 기준 계정을 객관식으로 고른다(기본 계정 포함, token-only 계정은 제외).
- plan: `create_dir token_dir (0700)` → 모든 대상에 블록 기록 → `registry_put`. 링크와 config 폴더 생성은 없다.
- add 화면과 README에 제약을 표시한다.
  - 세션 목록에서 다른 계정이 띄운 세션에 참여하면 그 세션을 띄운 계정의 토큰이 쓰인다. 계정을 바꾸려면 세션을 끝내고 `claude-<name> --resume <id>`로 다시 띄운다.
  - 기준 계정과 설정·권한·MCP·메모리·플러그인을 모두 공유한다.
  - `.claude.json`의 `oauthAccount`(화면 표시 이메일)는 공유되므로, 마지막으로 로그인한 계정의 이메일이 양쪽에 보일 수 있다. 실제 토큰은 분리돼 있다.
- login/logout/status는 `ap.sh run <name> -- claude auth ...`로 계정 env를 정확히 재현해서 실행한다.
- unlink(token-only): `claude auth logout`을 쓰지 않는다(공유 `.claude.json`의 표시 계정까지 지울 수 있기 때문). 대신 토큰 폴더를 아카이브 후 제거하고, macOS에서는 해당 키체인 항목(`Claude Code-credentials-<sha8>`)을 best-effort로 삭제한다. 공유 config 폴더는 절대 건드리지 않는다.

## 8. 플랫폼 계층

`scripts/platform.sh`(모든 bash 헬퍼가 source)

- `PYTHONUTF8=1`, `PYTHONIOENCODING=utf-8` export: Windows cp949 콘솔에서 한글과 `—` 출력 시 죽던 문제 해결.
- `python3` 함수: 실제 동작하는 인터프리터(`python3` → `python` 순, Windows Store stub 제외)로 위임한다. 없으면 설치 안내 후 실패.
- `AP_LIB` export: `aplib.py` 위치.

`aplib.py`

- `ap_os()`: `AP_OS_OVERRIDE` 우선, 그다음 `sys.platform`.
- `npath(p)`: Windows에서 `/c/...`, `/tmp/...` 같은 MSYS 경로를 네이티브 경로로 바꾼다. 네이티브 Python이 `/tmp`를 `C:\tmp`로 해석하던 문제를 해결한다.
- `make_link/remove_link/is_link`: Windows 디렉토리는 junction(`_winapi.CreateJunction`, 권한 불필요), 파일은 symlink(개발자 모드 필요, 실패 시 안내). junction 제거는 `os.rmdir`(대상 내용 보존). `rm -rf`로 junction을 지우지 않는다.
- 프로세스 생존 확인: Windows는 `tasklist`, 그 외 `kill -0`.

`safety.sh check-active`: 데몬 PID를 `daemon.lock`의 `pid`와 `daemon.status.json`의 `supervisorPid` 양쪽에서 읽는다(기존 코드는 status의 `pid`만 봐서 감지하지 못했다).

## 9. 테스트

- 기존 단위 테스트를 macOS와 Windows(Git Bash) 양쪽에서 통과하게 한다. OS 고유 검사(파일 권한 0600 등)는 해당 OS에서만 실행한다.
- `aplib_test.sh`(신규): 4종 블록 렌더링(OS mock), 블록 add/교체/제거(v0.4 형식 포함), CRLF·BOM·CP949 보존, 외부 정의 파서(이 PC의 실제 형태 포함), 서명 충돌 감지, registry, plan 실행·롤백, junction 생성·제거.
- 실기 검증: 이 Windows PC에서 adopt로 `claude-work`/`claude-han`/`claude-dami`를 통일하고 새 PowerShell, cmd, Git Bash 세션에서 env를 확인한다. macOS·Linux 실기 검증은 이 환경에서 불가능하므로 OS mock 단위 테스트로만 확인했다고 README에 명시한다.

## 10. 범위 밖

- fish 자동 기록(수동 안내만)
- 세션 참여 시 계정 전환(Claude Code 기능 요청 사항)
- 활성 세션 게이트의 토큰 폴더 단위 감지(Windows는 프로세스 env를 읽을 수 없음)
- 기존 Codex 리뷰 미반영 항목(P1-2, P1-4, P2)

## Needs Confirmation

pending: 없음 (사용자가 세부 확인 생략을 요청, 아래는 구현자 판단으로 결정한 항목) / resolved: 0

| # | 질문 | 선택지 | 권고와 이유 |
|---|---|---|---|
| Q1 | 릴리스 단위 | 0.5/0.6/0.7 단계 분리 vs 0.5.0 단일 | 0.5.0 단일. 사용자가 한 번에 진행을 원함. 커밋은 단계별로 나눔 |
| Q2 | token-only unlink 시 `claude auth logout` 사용 | 사용 vs 토큰 폴더 아카이브 | 아카이브. logout이 공유 `.claude.json`을 건드릴 수 있음 |
| Q3 | adopt 시 외부 정의 위의 주석 처리 | 유지 vs 함께 제거 | 바로 위에 붙은 주석만 함께 제거. 백업이 있어서 복구 가능 |
