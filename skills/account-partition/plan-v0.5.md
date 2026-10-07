# account-partition v0.5 (Windows 지원) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS + zsh 동작을 그대로 둔 채, Windows(Git Bash 헬퍼 + PowerShell 프로필)에서 add/list/edit/login/logout/unlink 6개 sub-skill이 junction 기반으로 동작하게 한다(v0.5.0).

**Architecture:** 새 `scripts/platform.sh`가 OS 판정·경로 변환·링크 생성/판정/제거·환경 감지·셸 블록 문자열·활성 세션 판정을 소유하고, 나머지 헬퍼는 이것을 source해 OS 분기를 위임한다. plan JSON은 무엇을 할지(`create_link {kind, method}` 등)를 담고, 실행 엔진(네이티브 Windows Python)은 링크·블록 작업을 직접 하지 않고 `platform.sh`/`shell-rc.sh`를 Git Bash로 호출한다. 기존 단위 테스트의 assert 문은 한 줄도 바꾸지 않고, macOS 출력은 `AP_OS_OVERRIDE=macos` 고정 테스트로 지킨다.

**Tech Stack:** bash (macOS bash 3.2 호환 유지 / Git Bash 5.2 MINGW64), Python 3 ≥ 3.8 (Windows는 네이티브 `win32` Python), Windows `cmd mklink /J`·`cmd rmdir`·`fsutil`·`tasklist`·`reg`·`powershell`, `cygpath`, 기존 `tests/unit/assert.sh` 하네스.

**Spec:** `skills/account-partition/design.md` §21 전체(D1~D7, §21.1~§21.8)와 §7. §21은 Windows에서 §7·§9·§11·§12·§13·§15보다 우선한다.

## Global Constraints

spec §21에서 그대로 옮긴다. 모든 task의 요구사항에 암묵적으로 포함된다.

- D1 검증 환경은 사용자 본인 Windows
- D2 헬퍼는 **Git Bash 재활용**. 기존 bash 헬퍼를 두고 경로, 셸, 링크만 OS 분기
- D3 디렉토리 공유는 **junction**
- D4 파일(`CLAUDE.md`) 공유는 **개발자 모드가 켜져 있으면 symlink, 꺼져 있으면 공유하지 않는다**. 켜는 법을 안내하고 조회에 "공유 안 됨"으로 표시한다
- D5 **처음에 OS 등 환경을 먼저 확인하고 그에 맞게 동작한다** (§21.1)
- D6 **프리셋 화면을 없애고 공유 항목을 바로 고른다** (§7). OS와 무관하게 적용
- D7 **macOS 지원은 그대로 유지한다.** v0.5는 Windows를 더하는 작업이다. macOS의 bash·fish와 Linux는 지금처럼 수동 안내. README·매니페스트의 "macOS+zsh" 표기를 "macOS + Windows"로 바꾼다
- **Windows에서 `ln -s`를 직접 부르는 코드를 두지 않는다.** 링크를 만든 모든 경로는 직후에 `ap_is_link`로 검사하고, 링크가 아니면 그 단계를 실패로 처리해 롤백한다(§11)
- plan JSON과 Python에 넘기는 모든 경로는 `cygpath -m` 형식(`C:/Users/gang/...`)으로만 담는다. `plan-build.sh`가 만들 때 변환한다
- `cmd //c mklink`에는 `cygpath -w` 형식을 넘기고 따옴표로 감싼다. 공백·한글 경로를 단위 테스트에 넣는다. `cmd` 출력은 cp949이므로 성공 판정은 출력 문자열이 아니라 exit code와 `ap_is_link`로 한다
- 계정 키는 `cygpath -m` 후 소문자로 정규화한다
- Python 쪽 판정은 `os.path.islink(p) or os.path.isjunction(p)`로 바꾸거나 `ap_is_link`를 호출한다. 롤백 테스트에 junction 케이스를 넣는다
- 링크일 수 있는 경로는 `rm -rf`로 지우지 않는다. 항상 `ap_unlink`를 쓴다
- `remove_dir`·`archive_dir` 전에 그 디렉토리 아래의 링크를 먼저 `ap_unlink`한다
- 삭제 함수에 넘기는 경로의 끝 `/`는 제거하고, 남아 있으면 실패시킨다
- tar는 링크를 링크로 복원하지 못한다(전제 2). 아카이브 복원 후 공유 항목은 링크를 다시 만드는 단계로 처리한다
- BOM으로 인코딩을 판정하고 원래 인코딩과 줄바꿈(CRLF)을 그대로 쓴다. 블록 내용은 ASCII만 쓴다
- UTF-16 프로필은 자동 편집하지 않고 수동 안내로 넘긴다
- 프로필 파일이 없으면 만든다. 디렉토리도 함께 만들고 UTF-8(BOM 없음), CRLF로 쓴다
- 시작·끝 마커 사이를 통째로 다루는 파서를 새로 둔다. 끝 마커가 없으면 지우지 않고 중단해 수동 안내로 넘긴다. 기존 zsh 블록 규칙(§12, 스킬이 만든 블록만 자동 편집)은 그대로다
- 차단 기준은 대상 config dir의 lockfile과 daemon 마커로 바꾼다. daemon PID 확인은 `kill -0`이 아니라 `tasklist /FI "PID eq <pid>"`로 한다
- 실행 중인 claude.exe 수는 경고로만 보여 준다: "다른 Claude 창이 N개 떠 있습니다. 대상 계정을 쓰는 창이면 닫고 진행하세요." macOS 동작은 그대로다
- 개발자 모드가 꺼진 Windows에서는 글로벌 인스트럭션을 선택지에서 빼고 이유를 질문에 적는다. 고를 수 있는데 실제로는 공유되지 않는 상황을 만들지 않는다
- `settings.json`은 여전히 선택지에 없다(격리 강제, §17). §21.5 수정은 v0.5에서 명령 출력만, 자동 편집하지 않는다
- macOS 단위 테스트 유지 (회귀 없게). `platform_test.sh`는 `AP_OS_OVERRIDE`로 OS를 고정한다. Windows 링크 검사는 실제 Windows에서만 도는 테스트로 분리한다
- 자유 텍스트 입력은 명령어 이름 1곳만, 나머지 결정은 `AskUserQuestion` (기존 UX 원칙, 각 SKILL.md "UX 원칙")
- 커밋 메시지 스타일: `feat(v0.5-N): <한국어 요약>` / `fix(v0.5-N): ...` / `chore: version 0.5.0 (...)` (git log의 `feat(v0.4.4-1)` 형식)

## Review Focus

spec이 암시하지만 spec 테스트 목록(§21.7)이 다루지 않는, 사용자가 가장 먼저 밟을 입력 5가지. 각 줄의 테스트는 해당 task에 추가했다.

1. **공백·한글이 든 경로** (한글 사용자 이름, `OneDrive\문서`, `tgt dir`) — junction 생성·판정·제거가 같은 결과를 내고, PowerShell 블록은 `$env:USERPROFILE`를 써서 ASCII로 남아야 한다. → Task 2 `[W-03]`, Task 6 `[P-10]`
2. **끝에 `/`가 붙은 junction 경로** (사용자가 공유 보관소를 `~/.claude-shared/`로 입력, `remove_dir` 인자) — 대상 내용을 지우지 않고 거부해야 한다. → Task 2 `[W-06]`, Task 3 `[D-02]`, `[D-05]`
3. **UTF-16 LE 프로필** (PowerShell 5.1 `Out-File`/`>`로 만든 프로필) — 자동 편집 없이 수동 안내, 파일은 바이트 단위로 그대로여야 한다. → Task 5 `[H-05]`
4. **기존 수동 함수 `claude-work`·`claude-dami`** (마커 없음, 환경변수 미복원, `~/.claude` 직결 junction) — 외부로 인식되고 어떤 자동 작업도 그 줄과 그 junction을 건드리지 않아야 한다. → Task 8 `[X-02]`~`[X-05]`, Task 5 `[H-08]`
5. **OneDrive 리디렉션 프로필** (`$PROFILE`이 `C:\Users\x\OneDrive\문서\WindowsPowerShell\...`, 파일·디렉토리 없음) — 감지가 PowerShell 출력(cp949)을 깨뜨리지 않고 경로를 그대로 얻고, 첫 자동 추가가 디렉토리와 파일을 만들어야 한다. → Task 4 `[W-14]`, Task 5 `[H-06]`

---

## 기준선과 근본 원인 (2026-10-07, 이 PC에서 측정)

`bash skills/account-partition/tests/unit/run.sh` → 132개 중 75 통과, 57 실패, exit 1.

| 파일 | 결과 | 근본 원인 (코드·실행으로 확인) |
|---|---|---|
| `plan_render_test.sh` | 0/17 | 경로가 아니라 **출력 인코딩**. Python stdout이 cp949라 `plan-render.sh:31`의 `—`(U+2014)에서 `UnicodeEncodeError`. 출력이 비어 모든 assert 실패 |
| `plan_shell_out_test.sh` | 0/19 | 같은 원인. `plan-shell-out.sh:24`의 `—` |
| `matrix_test.sh` | 0/11 | Python `subprocess.run(["bash", ...])`(`matrix.sh:35,53`)이 Windows 검색 순서상 `C:\Windows\System32\bash.exe`(WSL)를 실행: `execvpe(/bin/bash) failed` |
| `plan_rollback_test.sh` | 6/7 | 시나리오 3: 같은 WSL bash 문제(`plan-rollback.sh:79`). 시나리오 1의 통과는 **거짓 통과**: 테스트의 `ln -s`가 복사본을 만들어 `-L`이 원래부터 false |
| `plan_execute_test.sh` | 7/15 | plan JSON 안의 MSYS 경로(`/tmp/...`)를 네이티브 Python이 `C:\tmp\...`로 해석: `symlink source does not exist`, `archive_dir source missing` |
| `safety_test.sh` | 15/16 | `chmod 0600`이 `noacl` NTFS 마운트에서 효과 없음(`stat -c %a` = 644). `stat -f`는 GNU에서 파일시스템 정보를 출력 |

통과 75개 중에도 거짓 통과가 있다: `plan_build_test.sh`의 경로 assert는 MSYS가 환경변수 `/Users/test/...`를 `C:/Program Files/Git/Users/test/...`로 조용히 바꾼 결과를 부분 문자열로 맞힌 것이다(`plan-build.sh:9-11` env 전달, 재현함).

## 계획 중 새로 확인한 사실 (Task 1에서 `tests/preconditions.md` 검증 4로 옮긴다)

| # | 확인 | 결과 |
|---|---|---|
| F1 | Git Bash → 네이티브 프로그램 환경변수 | `/`로 시작하는 값은 MSYS가 자동 변환한다(`/tmp/a` → `C:/Users/<u>/AppData/Local/Temp/a`, `/Users/test` → `C:/Program Files/Git/Users/test`). `MSYS2_ENV_CONV_EXCL='*'`면 변환하지 않는다. `PATH`·`HOME`·`TEMP`는 그래도 변환된다 |
| F2 | 네이티브 Python의 `subprocess.run(["tar"])`, `(["bash"])` | System32의 `tar.exe`(bsdtar 3.8.8)와 `bash.exe`(WSL)가 실행된다. `shutil.which`는 Git의 것을 돌려주지만 실제 실행은 다르다. `rm`·`cp`·`mv`는 System32에 없어 Git 것이 실행된다 |
| F3 | `cmd //c mklink /J ...` | `/J`가 MSYS 인자 변환으로 깨져 "매개 변수가 틀립니다". `MSYS2_ARG_CONV_EXCL='*' cmd /c mklink /J "<w>" "<w>"` 또는 `//J`는 성공. 공백·한글 경로 성공 |
| F4 | `mklink /J`에 없는 대상 | 성공하고 끊어진 junction이 생긴다 → 대상 존재를 먼저 검사해야 한다 |
| F5 | junction 읽기 | Git Bash `readlink` = `/c/...` 형식. Python `os.readlink` = `\\?\C:\...`. Python `os.rmdir(junction)`·`cmd /c rmdir` 모두 대상 보존 |
| F6 | MSYS `tar` | `C:/...` 인자를 원격 호스트로 해석해 실패("Cannot connect to C:"). `--force-local`이면 성공. 안의 junction은 symlink 항목으로 저장되고 풀면 일반 디렉토리가 된다 |
| F7 | PowerShell 출력 인코딩 | 기본은 cp949(`문서` → `b9 ae bc ad`). `[Console]::OutputEncoding=[Text.Encoding]::UTF8;`를 앞에 두면 UTF-8 |
| F8 | 이 PC의 프로필 | `$PROFILE` = `C:\Users\gang\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`, UTF-8(BOM 없음), CRLF, 한글 주석 포함. ExecutionPolicy RemoteSigned, PowerShell 5.1.26100, `pwsh` 없음 |
| F9 | Claude Code 2.1.292 daemon 마커 | `daemon.status.json` 키 = `supervisorPid, supervisorProcStart, writtenAt, workers` (**`pid` 없음**). `daemon.lock`은 JSON이고 `pid` 키가 있다. 기존 `safety.sh:80-93`은 `status.pid`만 읽어 Windows에서 daemon을 못 찾는다 |
| F10 | `CLAUDE_CONFIG_DIR` 형식 | `C:\Users\gang\.claude-work`, `C:/Users/gang/.claude-work`, `/c/Users/gang/.claude-work` 모두 `claude auth status` `loggedIn: true`. 형식 차이로 로그인 상태가 갈리지 않는다 |
| F11 | Windows config dir | `~/.claude-work/.credentials.json`이 있다(자격 증명이 디렉토리 안 파일). unlink 아카이브에 들어갈 수 있다 — 범위 밖, 기록만 |
| F12 | PID | Git Bash `$$`는 MSYS PID. Windows PID는 `/proc/$$/winpid`. `tasklist`는 Windows PID만 안다 |

---

## 공통 계약 (Interfaces)

task 사이 결합점은 모두 여기 정의한다. 각 task의 Interfaces 블록은 이 절의 항목 이름을 가리킨다.

### A. `scripts/platform.sh` 함수 (source해서 쓰는 bash 함수)

용어: **host** = 실제 `uname -s`, **os** = `AP_OS_OVERRIDE`가 있으면 그 값, 없으면 host. **override 모드** = os ≠ host.

| 함수 | 인자 | stdout | exit | 규칙 |
|---|---|---|---|---|
| `ap_host_os` | - | `macos`/`windows`/`linux` | 0 | Darwin→macos, `MINGW*`/`MSYS*`→windows, 그 외 linux. override 무시 |
| `ap_os` | - | 같음 | 0, 잘못된 override면 64 | `AP_OS_OVERRIDE` ∈ {macos, windows, linux} |
| `ap_path_native` | `<path>` | 경로 | 0 | os=windows이고 host=windows일 때만 `cygpath -m`. 그 외(override 모드 포함) 입력 그대로 |
| `ap_path_win` | `<path>` | `C:\...` | 0, host≠windows면 64 | `cygpath -w` |
| `ap_path_key` | `<path>` | 키 | 0 | `ap_path_native` → 끝 `/` 제거 → os=windows면 소문자 |
| `ap_devmode` | - | `on`/`off`/`n/a` | 0 | `AP_DEVMODE_OVERRIDE`(on/off) 우선. host=windows면 `MSYS2_ARG_CONV_EXCL='*' reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense` exit 0이고 출력에 `0x1` → on, 아니면 off. os≠windows → `n/a`. os=windows이고 host≠windows이며 override 없음 → off |
| `ap_link_method` | `dir`\|`file` | `symlink`/`junction`/`none` | 0 | macos·linux → symlink. windows dir → junction. windows file → `ap_devmode`=on이면 symlink, 아니면 none |
| `ap_link_dir` | `<target> <link>` | - | 0 성공 / 1 실패 / 64 override 모드 | 사전: target이 디렉토리, link 경로 없음, 두 인자 끝 `/` 없음. windows: `MSYS2_ARG_CONV_EXCL='*' cmd /c mklink /J "<link -w>" "<target -w>" >/dev/null 2>&1`. macos: `ln -s -- target link`. 사후: `ap_is_link link` 실패면 만들어진 경로가 링크가 아님을 확인한 뒤 그 경로를 지우고 1 ("created path is not a link") |
| `ap_link_file` | `<target> <link>` | - | 0 / 1 / 2 수단 없음 / 64 | `ap_link_method file`=none → 2 ("file link unavailable: developer mode off"), 아무것도 만들지 않음. windows+symlink: `MSYS=winsymlinks:nativestrict ln -s -- target link`. 사후 검사는 `ap_link_dir`과 같음 |
| `ap_is_link` | `<path>` | - | 0 링크 / 1 아님 / 2 끝 `/` | windows: `MSYS2_ARG_CONV_EXCL='*' fsutil reparsepoint query "<-w>"` 출력에 `0xa0000003` 또는 `0xa000000c`(대소문자 무시). macos: `[ -L ]` |
| `ap_link_target` | `<path>` | 대상 (native) | 0 / 1 링크 아님 | `ap_path_native "$(readlink -- path)"` |
| `ap_unlink` | `<path>` | - | 0 / 1 / 64 | 끝 `/` → 1 ("trailing slash refused"). `ap_is_link` 아님 → 1 ("not a link; refusing"), 아무것도 지우지 않음. windows: `MSYS2_ARG_CONV_EXCL='*' cmd /c rmdir "<-w>"`, 남아 있으면 `rm -f -- path`. macos: `rm -f -- path`. 사후 경로가 남아 있으면 1 |
| `ap_unlink_under` | `<dir>` | 제거한 링크를 `rel<TAB>target<TAB>kind` 한 줄씩 | 0 / 1 | `<dir>` 끝 `/` → 1. 실제 디렉토리만 따라 내려가며 링크는 `ap_unlink`(내려가지 않음). kind = 대상이 디렉토리면 `dir`, 아니면 `file` |
| `ap_alias_block` | `<name> <config_dir> <format>` | 블록 줄 | 0 / 3 ASCII 불가 | §E 형식. format ∈ {zsh, powershell} |
| `ap_ps_eval` | `<exe> <expr>` | 결과 (CR 제거) | exe exit | `MSYS2_ARG_CONV_EXCL='*' "<exe>" -NoProfile -NonInteractive -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; <expr>"` |
| `ap_env_detect` | - | 감지 JSON (§C `detected`) | 0 / 5 Python 없음 / 64 | override 모드면 64. `AP_TEST_MODE=1`이고 `AP_DETECT_FIXTURE`가 있으면 그 파일 내용을 그대로 출력 |
| `ap_python_ok` | - | - | 0 / 5 | `"${AP_PYTHON:-python3}" -c 'import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)'` exit 0이면 0. Store 스텁(exit 9009)·미설치·3.8 미만 → 5 |
| `ap_shell_rc` | - | 확인된 셸 통합 파일 (native) | 0 / 2 수동·미확인 | 환경 파일 `choice.shell_rc` |
| `ap_check_active` | `<config_dir>` | 사유 한 줄 / 경고 | 0 활성(차단) / 1 비활성 | Task 10. macos·linux 분기는 `safety.sh:73-107`의 기존 본문을 그대로 옮긴다 |

`platform.sh`를 source하면 다음을 export한다(모든 host): `PYTHONUTF8=1`, `PYTHONIOENCODING=utf-8`, `AP_BASH` = `ap_path_native "$BASH"`, `AP_TAR` = `ap_path_native "$(command -v tar)"`, `AP_PLATFORM` = 자기 경로(native), `AP_OS` = `ap_os`. host=windows면 추가로 `MSYS2_ENV_CONV_EXCL='*'`.

함수가 실패 사유를 낼 때는 stderr에 `account-partition: <함수>: <영문 사유>` 한 줄.

### B. `platform.sh` CLI (`bash platform.sh <cmd> ...`)

source가 아닐 때(`[[ "${BASH_SOURCE[0]}" == "$0" ]]`)만 dispatch한다. exit code는 함수 그대로.

`os`, `host-os`, `path-native <p>`, `path-key <p>`, `devmode`, `link-method <dir|file>`, `link-dir <target> <link>`, `link-file <target> <link>`, `is-link <p>`, `link-target <p>`, `unlink <p>`, `unlink-under <dir>`, `alias-block <name> <config_dir> <format>`, `detect`, `env-check`, `env-save <shell_target>`, `env-summary`, `shell-rc`, `block-file <name>`, `record-block <name> <file> <format>`, `forget-block <name>`, `check-active <config_dir>`. 알 수 없는 cmd → 사용법 stderr, exit 1.

| cmd | stdout | exit |
|---|---|---|
| `env-check` | `{"status": "same"\|"changed"\|"first", "changed": [키...], "detected": {...}, "choice": {...}\|null}` | 0 same / 3 changed / 4 first / 5 Python 없음(이때 stdout은 한국어 안내 한 줄, JSON 아님) |
| `env-save <shell_target>` | 저장한 환경 파일 경로 | 0 / 2 (`shell_target`이 감지 후보도 `manual`도 아님, 파일 불변) |
| `env-summary` | 확인 질문 본문 줄 (§C 끝) | 0 / 4 환경 파일 없음 |
| `block-file <name>` | `blocks[name].file`, 없으면 `choice.shell_rc` | 0 / 2 둘 다 없음 |

### C. 환경 파일 `~/.account-partition-env.json` (경로 override: `AP_ENV_FILE`)

```json
{
  "schema": 1,
  "detected": {
    "os": "windows",
    "os_label": "Windows 11",
    "python": {"ok": true, "version": "3.12.5"},
    "shells": [
      {"id": "ps51", "label": "PowerShell 5.1",
       "profile": "C:/Users/gang/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1",
       "exists": true, "encoding": "utf-8", "execution_policy": "RemoteSigned"}
    ],
    "link_dir": "junction",
    "link_file": "none",
    "devmode": "off"
  },
  "choice": {"shell_target": "ps51",
             "shell_rc": "C:/Users/gang/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1",
             "confirmed_at": "2026-10-07T15:00:00+09:00"},
  "blocks": {"side": {"file": "C:/Users/gang/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1",
                      "format": "powershell", "recorded_at": "2026-10-07T15:01:00+09:00"}}
}
```

- **감지 스냅샷**(`detected`): 다음 호출이 비교하는 유일한 대상. 비교 키 집합(그리고 `changed` 배열의 이름, 이 순서): `os`, `python.ok`, `shells.id`, `shells.profile`, `shells.execution_policy`, `link_dir`, `link_file`, `devmode`. `os_label`·버전·`exists`·`encoding`은 비교하지 않는다.
- **사용자 선택**(`choice`): 비교하지 않는다. `shell_target` ∈ {`zsh`, `ps51`, `pwsh`, `manual`}. `manual`이면 `shell_rc: null`.
- **계정별 블록 파일**(`blocks`): `record-block`/`forget-block`만 바꾼다. `env-save`는 보존한다. 셸 통합 대상을 바꿔도 unlink가 옛 프로필의 블록을 찾게 하는 것이 목적(§21.1 3).
- 감지 규칙: macos → `$SHELL` basename이 `zsh`면 `shells=[{"id":"zsh","label":"zsh","profile":"$HOME/.zshrc"(native),...,"execution_policy":null}]`, 아니면 `[]`. windows → `powershell`로 `ap_ps_eval powershell '$PROFILE; Get-ExecutionPolicy; $PSVersionTable.PSVersion.ToString()'`(세 줄) → `ps51`; `command -v pwsh`가 있으면 같은 식으로 `pwsh`. `os_label`: uname의 빌드 번호 ≥ 22000 → `Windows 11`, 아니면 `Windows 10`. `link_dir`/`link_file` = `ap_link_method`. `encoding` = `shell-rc.sh encoding <profile>`(Task 5 전에는 `"unknown"`).
- 쓰기는 같은 디렉토리 임시 파일 → `os.replace`. UTF-8.
- `env-summary` 줄 (windows, 개발자 모드 꺼짐):
  ```
  Windows 11 · PowerShell 5.1 (프로필: C:\Users\gang\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1)
  디렉토리 공유: junction / CLAUDE.md 공유: 안 함 (개발자 모드 꺼짐)
  ```
  켜짐이면 둘째 줄 끝이 `CLAUDE.md 공유: symlink`. 선택된 셸의 `execution_policy`가 `Restricted`면 셋째 줄 `실행 정책이 Restricted라 프로필 함수가 로드되지 않습니다. PowerShell에서 실행: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`. macos: `macOS · zsh (~/.zshrc)` / `디렉토리 공유: symlink / CLAUDE.md 공유: symlink`. 셸 후보 0개면 첫 줄 셸 부분이 `셸 통합: 수동 안내`.

### D. plan op 스키마 (v0.5)

경로 값은 모두 `ap_path_native` 결과이고 끝 `/`가 없다. `metadata`에 `"os": <ap_os>`와 `"skipped": [{"item": "CLAUDE.md", "reason": "file_link_unavailable"}]`(해당 시)를 더한다.

| op | 필드 | 실행 엔진이 기록하는 메타 |
|---|---|---|
| `create_dir` | `path`, `mode` | - |
| `create_link` | `kind`: `dir`\|`file`, `method`: `symlink`\|`junction`, `src`(대상), `dst`(링크), `backup_if_exists` | `_backup_path`, `_prev_link_target`, `_prev_link_kind` |
| `create_symlink` (구 plan 호환, 새로 만들지 않음) | `src`, `dst`, `backup_if_exists` | 실행 시 `kind` = src가 디렉토리면 `dir` 아니면 `file`, `method` = `ap_link_method kind`로 `create_link`와 같게 처리 |
| `remove_symlink` (이름 유지, 링크 종류 무관) | `dst` | `_link_target`, `_link_kind` |
| `copy` / `move` | `src`, `dst` | - |
| `quarantine` | `path`, `config_dir` | - |
| `append_block` | `file`, `format`: `zsh`\|`powershell`(없으면 zsh), `marker`, `end_marker`(powershell만), `lines`(마커 사이 본문), `backup`, `name` | `_backup_path` |
| `remove_block` | `file`, `format`, `marker`, `end_marker`(powershell만), `name` | - |
| `auth_logout` | `config_dir` | - |
| `archive_dir` | `src` | `_archive_path`, `_links`: `[{"rel", "target", "kind"}]`, 사이드카 `<archive>.links.json` |
| `remove_dir` | `path` | `_links` |

### E. 셸 블록 형식과 마커

zsh (`format: zsh`, 기존과 같음, 2줄):
```
# account-partition: <name>
alias claude-<name>="CLAUDE_CONFIG_DIR=$HOME/.claude-<name> command claude"
```
config_dir가 `$HOME` 아래면 그 접두를 문자 그대로 `$HOME`으로 바꾼다(`plan-build.sh:38` 기존 규칙). 아니면 경로 그대로.

PowerShell (`format: powershell`, spec §21.3 원문, 들여쓰기 4칸, ASCII만):
```
# account-partition: <name>
function claude-<name> {
    $prev = $env:CLAUDE_CONFIG_DIR
    try {
        $env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\.claude-<name>"
        & claude @args
    } finally {
        if ($null -eq $prev) { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
        else { $env:CLAUDE_CONFIG_DIR = $prev }
    }
}
# /account-partition: <name>
```
config_dir 키가 HOME 키 아래면 `"$env:USERPROFILE\<HOME 아래 상대경로, / → \>"`, 아니면 `"<ap_path_win 결과>"`. 결과 블록에 ASCII 아닌 바이트가 있으면 exit 3(수동 안내). 시작 마커 = `# account-partition: <name>`, 끝 마커 = `# /account-partition: <name>`(줄 앞뒤 공백 무시, 정확히 일치). 셸 파일 형식 판정은 OS가 아니라 **파일 확장자**: `*.ps1` → powershell, 그 외 → zsh.

### F. 실행 엔진 Python 헬퍼 (`plan-execute.sh`·`plan-rollback.sh`·`matrix.sh` 안에 같은 이름으로)

- `_is_link(p) -> bool`: `os.path.islink(p)` 이거나, `sys.platform == "win32"`이고 `os.lstat(p).st_reparse_tag == 0xA0000003`(junction). `OSError` → False. (spec의 `isjunction`과 같은 판정이며 Python 3.8부터 동작)
- `_link_target(p) -> str`: `os.readlink(p)`에서 앞의 `\\?\` 제거, `\` → `/`.
- `_key(p) -> str`: 끝 `/` 제거, win32면 `lower()`. bash `ap_path_key`와 같은 결과여야 한다(`[K-01]`).
- `_native(p) -> str`: win32에서 `re.match(r"^[A-Za-z]:/", p)`가 아니면 `ValueError("경로 계약 위반(cygpath -m 형식 아님): " + p)`. 다른 OS는 그대로.
- `_no_trailing(p) -> str`: `p.endswith(("/", "\\"))`이고 루트가 아니면 `ValueError("trailing slash refused: " + p)`.
- `_plat(*args) -> CompletedProcess`: `subprocess.run([os.environ["AP_BASH"], os.environ["AP_PLATFORM"], *args], capture_output=True, text=True)`.
- 외부 프로그램 이름 규칙: `"bash"`·`"tar"`를 이름으로 실행하지 않는다. `AP_BASH`, `AP_TAR`(win32면 `--force-local` 추가)를 쓴다.
- op는 원자적이다: op 안에서 예외가 나면 그 op가 한 변경(백업 이동 등)을 되돌린 뒤 다시 raise한다.

### G. 테스트 하네스와 테스트 ID

- 테스트 ID는 assert 메시지 앞머리 `[XX-NN]`. DoD는 `<파일>::[XX-NN]`으로 가리킨다.
- `assert.sh` 추가·변경(Task 1·2):
  - `make_sandbox`: host=windows면 `cygpath -m`한 경로를 돌려준다(기존 macOS 동작 그대로).
  - `assert_symlink_target`: host=windows면 `readlink` 결과와 기대값을 둘 다 `cygpath -m`해 비교. 성공·실패 메시지 형식 그대로.
  - `AP_FX_PLATFORM` = `scripts/platform.sh` 절대경로.
  - `fx_link <target> <link>`: target이 디렉토리면 `platform.sh link-dir`, 아니면 `link-file`. 실패면 `✗ fx_link failed` 한 건 실패로 센다.
  - `fx_file_links_supported`: `platform.sh link-method file` ≠ `none`이면 0.
  - `fx_skip <id> <reason>`: `  - SKIP <id>: <reason>` 출력, 집계에 넣지 않는다.
  - `fx_native_pid`: host=windows면 `cat /proc/$$/winpid`, 아니면 `$$`.
  - `fx_windows_only`: host≠windows면 `SKIP: windows host only` 출력 후 `exit 0`.
- 기존 9개 테스트 파일의 `assert_*` 호출 줄과 `✓`/`✗` echo 줄은 문자 그대로 남긴다(들여쓰기만 바뀔 수 있음). 바뀌는 것은 fixture(경로 형식, 링크 생성)와 capability 게이트뿐이다. `tests/unit/check_assertions_unchanged.sh`(Task 1)가 이것을 검사한다.

---

## File Structure

| 파일 | 상태 | 책임 |
|---|---|---|
| `skills/account-partition/scripts/platform.sh` | 신규 | §A·§B·§C 전부 |
| `skills/account-partition/scripts/marketplace.sh` | 신규 | §21.5 주소 대조 |
| `skills/account-partition/scripts/{plan-execute,plan-rollback}.sh` | 수정 | §D·§F, 삭제 규칙 |
| `skills/account-partition/scripts/{plan-build,plan-render,plan-shell-out}.sh` | 수정 | op 스키마 v0.5, OS별 문자열 |
| `skills/account-partition/scripts/shell-rc.sh` | 수정 | `.ps1` 편집·파서·인코딩, `write-block`, `list-detail` |
| `skills/account-partition/scripts/{discover,matrix,safety}.sh` | 수정 | 외부 계정·키 정규화·표시·활성 세션 |
| `skills/account-partition/tests/unit/assert.sh` | 수정 | §G |
| `skills/account-partition/tests/unit/` 신규 테스트 | 신규 | `platform_test.sh`, `platform_windows_test.sh`, `link_engine_test.sh`, `engine_delete_test.sh`, `engine_rules_test.sh`, `env_test.sh`, `shell_rc_ps_test.sh`, `plan_build_os_test.sh`, `discover_ext_test.sh`, `marketplace_test.sh`, `docs_contract_test.sh`, 검사기 `check_assertions_unchanged.sh` |
| `skills/account-partition/references/env-check.md` | 신규 | Step 0 질문 원문·분기 (7개 SKILL이 공유) |
| `skills/*/SKILL.md` (7개), `commands/unlink.md`, `README.md`, `.claude-plugin/*.json`, `references/shell-integration.md`, `references/item-mapping.md`, `tests/preconditions.md`, `tests/manual.md`, `design.md` §11·§17 | 수정 | 문서 |

---

## Task 1: 경로 계약과 Python 호출 계약 — Windows 기존 테스트 복구 [TDD]

**Files:**
- Create: `skills/account-partition/scripts/platform.sh` (§A 중 `ap_host_os`, `ap_os`, `ap_path_native`, `ap_path_win`, `ap_path_key`, export 블록, §B 중 `os`·`host-os`·`path-native`·`path-key`)
- Create: `skills/account-partition/tests/unit/platform_test.sh`, `tests/unit/platform_windows_test.sh`, `tests/unit/check_assertions_unchanged.sh`
- Modify: `scripts/plan-execute.sh:15-207`, `scripts/plan-rollback.sh:9-131`, `scripts/matrix.sh:9-176`, `scripts/discover.sh:14-96`, `scripts/shell-rc.sh:43-113`, `scripts/safety.sh:73-94`, `scripts/plan-build.sh:5-159`, `scripts/plan-render.sh:5-10`, `scripts/plan-shell-out.sh:4-10`
- Modify: `tests/unit/assert.sh:64-96`, `tests/unit/safety_test.sh:51-53`
- Modify: `tests/preconditions.md` (검증 4 추가), `design.md` §17 파일 권한 (DECISION-1 결과 한 줄)

**Interfaces:**
- Consumes: 없음
- Produces: §A의 경로 함수와 export(`AP_BASH`, `AP_TAR`, `AP_PLATFORM`, `AP_OS`, `PYTHONUTF8`, `PYTHONIOENCODING`, windows의 `MSYS2_ENV_CONV_EXCL`), §F의 `_is_link`·`_link_target`·`_key`·`_native`, §G의 `make_sandbox`(native)·`assert_symlink_target`(정규화)·`fx_windows_only`

- [ ] **Step 1: 실패 테스트 작성** — `platform_test.sh`(모든 host), `platform_windows_test.sh`(첫 줄 `fx_windows_only`)

  | ID | 입력 | 단정 |
  |---|---|---|
  | `[P-01]` | `AP_OS_OVERRIDE=windows bash platform.sh os` / override 없음 | `windows` / host 값(Darwin→`macos`, MINGW→`windows`) |
  | `[P-02]` | `AP_OS_OVERRIDE=solaris bash platform.sh os` | exit 64 |
  | `[P-03]` | override 모드(host와 다른 값)에서 `path-native /Users/test/a` | `/Users/test/a` 그대로 |
  | `[P-04]` | `AP_OS_OVERRIDE=macos path-key /Users/A/.claude-x/` | `/Users/A/.claude-x` (대소문자 유지) |
  | `[P-12]` | platform.sh source 후 `python3 -c 'print("\u2014\u2713")'` | exit 0, 출력 `—✓` |
  | `[P-13]` | source 후 `"$AP_BASH" -c 'echo ok'`, 그리고 `python3 -c 'import os,subprocess;print(subprocess.run([os.environ["AP_BASH"],"-c","echo $BASH_VERSION"],capture_output=True,text=True).stdout.strip())'` | `ok`, 두 번째는 비어 있지 않고 `WSL` 문자열 없음 |
  | `[W-01]` | `path-native /c/Users/x/a\ b/한글`, `path-native "$(cygpath -u "$TEMP")"` | `C:/Users/x/a b/한글`, `^[A-Z]:/` |
  | `[W-02]` | `path-key` of `C:\Users\Gang\.claude-X`, `C:/users/gang/.claude-x/`, `/c/Users/gang/.claude-x` | 셋 다 `c:/users/gang/.claude-x` |
  | `[K-01]` | `[W-02]`의 세 입력을 `plan-execute.sh`와 같은 `_key` 구현(Python 원문을 테스트가 `matrix.sh`에서 추출하지 않고 `bash platform.sh path-native` 결과에 `_key` 규칙을 Python으로 적용) | bash `path-key`와 같은 문자열 |
  | `[W-15]` | plan JSON에 `"/tmp/x"` 경로를 담아 `plan-execute.sh` 실행 | exit 2, 상태 파일 `_error`에 `경로 계약 위반` 포함 |

  `check_assertions_unchanged.sh <base-ref> [--tree <tests/unit 디렉토리>]`(기본 tree = 스크립트가 있는 디렉토리): 기존 9개 파일 각각에 대해 `git show <base-ref>:skills/account-partition/tests/unit/<file>`과 tree의 같은 파일에서 `assert_(eq|contains|file_exists|symlink_target) ` 호출 줄과 `echo "  ✓`/`echo "  ✗` 줄을 앞 공백을 지우고 뽑아, 기준의 모든 줄이 작업 트리에 (개수 포함) 남아 있으면 exit 0, 하나라도 없으면 없는 줄을 출력하고 exit 1.

- [ ] **Step 2: RED 확인**

  Run: `bash skills/account-partition/tests/unit/run.sh`
  Expected: exit 1. 기준선 57건 실패 그대로 + `platform_test.sh`·`platform_windows_test.sh` 실패(`platform.sh` 없음은 RED로 치지 않으므로, 빈 `platform.sh`(dispatch 없음)를 먼저 두고 `[P-01]`이 `expected: windows actual:`로 실패하는 것을 확인)

- [ ] **Step 3: `platform.sh` 경로 계층 구현** — §A 해당 행 그대로. bash 3.2 호환(연관 배열·`${var,,}` 금지, 소문자는 `tr`).

- [ ] **Step 4: 헬퍼를 경로 계약에 맞춘다**
  - 모든 `scripts/*.sh` 첫 실행 줄에 `source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/platform.sh"`.
  - bash가 Python에 env로 넘기는 경로 값을 모두 `ap_path_native`로 바꾼다: `plan-execute.sh`의 `STATE_FILE_ENV`·`SCRIPTS_DIR_ENV`, `plan-rollback.sh`의 같은 둘, `matrix.sh`의 `HOME_ENV`·`SHARED_POOL_ENV`·`SCRIPTS_DIR_ENV`, `discover.sh`의 `CLAUDE_JSON_PATH`·`AP_DIR`, `shell-rc.sh`의 `RC_PATH`, `safety.sh`의 `STATUS_PATH`, `plan-build.sh`의 `CONFIG_DIR`·`SHARED_POOL`·`SHELL_RC`(값의 끝 `/`도 제거).
  - `discover.sh` `list-dirs`/`list-ignored` 출력과 `meta`의 `dir`을 `ap_path_native`로. 공유 보관소·default 비교는 `ap_path_key`끼리(`discover.sh:17-24,29,40,55`).
  - Python의 `subprocess.run(["bash", ...])`를 `os.environ["AP_BASH"]`로(`matrix.sh:35,53`, `plan-execute.sh:59,144`, `plan-rollback.sh:79`). `["tar", ...]`를 `AP_TAR` + win32 `--force-local`로(`plan-execute.sh:177,179`, `plan-rollback.sh:118`).
  - `plan-execute.sh`·`plan-rollback.sh`·`matrix.sh`에 §F 헬퍼를 두고, `os.path.islink`·`os.readlink` 호출을 `_is_link`·`_link_target`으로(`plan-execute.sh:80,89`, `plan-rollback.sh:51`, `matrix.sh:124-143`). 실행 엔진은 op마다 경로 필드에 `_native`를 적용한다(실패는 기존 예외 경로로 → 상태 파일 기록, exit 2).
  - `create_symlink`의 백업을 `cp -Rp` + `rm -rf`(`plan-execute.sh:80-85`)에서 `os.replace(dst, backup)`로 바꾸고, 같은 op 안에서 링크 생성이 실패하면 `os.replace(backup, dst)`로 되돌린 뒤 raise(§F 원자성).
- [ ] **Step 5: 하네스·safety 테스트 fixture** — `assert.sh`의 `make_sandbox`·`assert_symlink_target`·`fx_windows_only`(§G). `safety_test.sh:52-53` 권한 단정을 DECISION-1 기본안대로 `if [[ "$(bash "$AP_FX_PLATFORM" host-os)" != windows ]]; then <기존 두 줄 그대로> else fx_skip S-perm "noacl NTFS: chmod 무효(§17 주)"; fi`로 감싼다.
- [ ] **Step 6: 문서** — `tests/preconditions.md`에 "검증 4: v0.5 계획 중 확인 (2026-10-07)" 표로 F1~F12를 옮긴다. `design.md` §17 "파일 권한"에 "Windows(Git Bash noacl)에서는 chmod가 효과 없다. 사용자 프로필 ACL 상속에 의존한다" 한 줄(DECISION-1 기본안 기준).
- [ ] **Step 7: GREEN 확인**

  Run: `bash skills/account-partition/tests/unit/run.sh`
  Expected (이 PC, 개발자 모드 꺼짐): `plan_execute_test.sh`만 실패(`Tests: 15  Pass: 11  Fail: 4` — 시나리오 1의 `symlink .../settings.json`, `marker 추가`, `alias 추가`, `성공 후 상태 파일 잔존`; 파일 링크가 불가능해서이며 Task 2가 게이트로 처리). 나머지 파일 전부 Fail 0. `platform_test.sh`·`platform_windows_test.sh` Fail 0.

  Run: `bash skills/account-partition/tests/unit/check_assertions_unchanged.sh ca598df`
  Expected: exit 0

- [ ] **Step 8: Commit**

  ```bash
  git add skills/account-partition/scripts skills/account-partition/tests skills/account-partition/design.md
  git commit -m "feat(v0.5-1): 경로 계약·Python 호출 계약 — Windows에서 기존 단위 테스트 복구"
  ```

## Task 2: 링크 계층과 `create_link` op [TDD]

**Files:**
- Modify: `scripts/platform.sh` (+ `ap_devmode`, `ap_link_method`, `ap_link_dir`, `ap_link_file`, `ap_is_link`, `ap_link_target`, `ap_unlink`; CLI 해당 cmd)
- Modify: `scripts/plan-execute.sh` (`create_symlink`→`create_link` 처리, `remove_symlink`), `scripts/plan-rollback.sh` (`create_link`·`create_symlink`·`remove_symlink` 롤백)
- Create: `tests/unit/link_engine_test.sh`
- Modify: `tests/unit/platform_test.sh`, `platform_windows_test.sh`, `assert.sh` (`fx_link`, `fx_file_links_supported`, `fx_skip`)
- Modify (게이트만): `tests/unit/plan_execute_test.sh:13-43,147-186`, `plan_rollback_test.sh:10-48`, `matrix_test.sh:10-21`

**Interfaces:**
- Consumes: Task 1의 `ap_path_native`, `ap_path_win`, `_is_link`, `_native`, `AP_BASH`, `AP_PLATFORM`, `_plat`
- Produces: §A 링크 함수와 CLI, §D `create_link` 실행·롤백, 메타 `_backup_path`·`_prev_link_target`·`_prev_link_kind`·`_link_target`·`_link_kind`, 테스트 주입 `AP_TEST_MODE=1` + `AP_TEST_LINK_FAULT=copy`(→ `ap_link_dir`/`ap_link_file`이 링크 대신 `cp -R target link`를 만든 뒤 사후 검사를 그대로 돈다)

- [ ] **Step 1: 실패 테스트 작성**

  | ID | 파일 | 입력 | 단정 |
  |---|---|---|---|
  | `[P-05]` | platform_test | `AP_OS_OVERRIDE=macos link-method dir`/`file` | `symlink`/`symlink` |
  | `[P-06]` | platform_test | `AP_OS_OVERRIDE=windows` + `AP_DEVMODE_OVERRIDE=on`/`off`, dir/file | `junction`; file on→`symlink`, off→`none` |
  | `[P-11]` | platform_test | override 모드에서 `link-dir`, `link-file`, `unlink`, `is-link` | 각각 exit 64, 샌드박스에 새 파일 0개 |
  | `[W-03]` | windows | 대상 `"$sb/tgt dir/한글"`(파일 1개), `link-dir` → `"$sb/lnk 한"` | exit 0; `is-link` 0; `fsutil` 출력에 `0xa0000003`; 링크 경로로 쓴 파일이 대상에 보임 |
  | `[W-04]` | windows | 없는 대상으로 `link-dir` | exit 1, 링크 경로 없음 |
  | `[W-05]` | windows | `[W-03]` 링크에 `unlink` | exit 0, 링크 경로 없음, 대상 파일 수 그대로 |
  | `[W-06]` | windows | `unlink "$sb/lnk 한/"` | exit 1, 링크·대상 그대로 |
  | `[W-07]` | windows | 실제 디렉토리에 `unlink` | exit 1, 디렉토리와 내용 그대로 |
  | `[W-08]` | windows | `AP_TEST_MODE=1 AP_TEST_LINK_FAULT=copy link-dir` | exit 1, 링크 경로 없음, 대상 그대로 |
  | `[W-09]` | windows | `AP_DEVMODE_OVERRIDE=off link-file` | exit 2, 링크 경로 없음 |
  | `[W-10]` | windows | Git Bash `ln -s`로 만든 경로에 `is-link` | exit 1 (복사본 검출) |
  | `[W-11]` | windows | `link-target "$sb/lnk 한"` | `path-native "$sb/tgt dir/한글"`과 같음 |
  | `[E-01]` | link_engine | `create_link {kind: dir, method: <ap_link_method dir>}` | 실행 exit 0, `dst` is-link, 대상 = src, 상태 파일 없음 |
  | `[E-02]` | link_engine | dst가 실제 디렉토리(파일 `a`), `backup_if_exists: true` | `dst.bak.*` 하나 생기고 그 안에 `a`, dst는 링크 |
  | `[E-03]` | link_engine | windows+`AP_DEVMODE_OVERRIDE=off`, `create_link {kind: file}`, dst에 기존 파일 | exit 2, dst 내용 그대로, `.bak.*` 0개 (macos host: `fx_skip`) |
  | `[E-04]` | link_engine | `AP_TEST_MODE=1 AP_TEST_LINK_FAULT=copy`, dst 기존 디렉토리, `backup_if_exists` | 실행 exit 2 → `plan-rollback.sh` 후 dst는 링크 아님, 원래 내용 복원, src 파일 수 그대로 |
  | `[E-05]` | link_engine | dst = src를 향한 링크; `remove_symlink` 후 `copy src→dst` | dst는 실제 디렉토리, `dst/<src basename>` 없음(중첩 없음), src 파일 수 그대로 |
  | `[E-06]` | link_engine | dst가 실제 디렉토리에서 `remove_symlink` | exit 2, `_error`에 `not a link`, dst 그대로 |
  | `[E-08]` | link_engine | `remove_symlink` 성공 후 다음 op 실패 → 롤백 | dst가 다시 링크, 대상 = 원래 src |
  | `[E-09]` | link_engine | `create_link` 성공 후 실패 → 롤백 | dst 없음(또는 백업 복원), src 내용이 공유 보관소 안으로 옮겨지지 않음(src 파일 목록 그대로) |
  | `[E-11]` | link_engine | 구 op `create_symlink`(src 디렉토리) | `[E-01]`과 같은 결과 |

  기존 테스트 게이트(assert 줄 불변): `plan_execute_test.sh` 시나리오 1·5와 `plan_rollback_test.sh` 시나리오 1을 `if fx_file_links_supported; then <원문 블록> else fx_skip <S1|S5|R1> "file link unavailable (developer mode off)"; <디렉토리 변형> fi`로 감싼다. 디렉토리 변형은 같은 흐름에서 `settings.json`/`item` 대신 디렉토리 `plugins`를 쓰고 메시지에 `[S1w]`/`[S5w]`/`[R1w]`를 붙인 같은 종류의 assert. 테스트 준비의 `ln -s`(`matrix_test.sh:13,21`, `plan_rollback_test.sh:14`)는 `fx_link`로 바꾸고, 파일 링크 줄은 `fx_file_links_supported`일 때만.

- [ ] **Step 2: RED 확인**

  Run: `bash skills/account-partition/tests/unit/link_engine_test.sh`
  Expected: FAIL — `[E-01]` 실행 결과 `unknown op: create_link`
  Run: `bash skills/account-partition/tests/unit/platform_windows_test.sh`
  Expected: FAIL — `[W-03]` `link-dir` 사용법 오류(exit 1)

- [ ] **Step 3: `platform.sh` 링크 함수 구현** — §A 행 그대로. junction 판정은 `fsutil`, 생성 성공은 exit code + `ap_is_link`만으로 판단(출력 문자열 금지).
- [ ] **Step 4: 실행 엔진**
  - `create_link`: 순서 = `_native`/`_no_trailing` 검사 → `kind=file`이고 `method=none`(또는 `_plat("link-method","file")`가 `none`)이면 dst를 건드리기 전에 `RuntimeError("file link unavailable: developer mode off")` → dst가 `_is_link`면 `_prev_link_target`·`_prev_link_kind` 기록 후 `_plat("unlink", dst)` → dst가 실제 경로면 `os.replace(dst, dst + ".bak." + unique_ts())`, `_backup_path` 기록 → `_plat("link-dir"|"link-file", src, dst)` exit ≠ 0이면 백업·이전 링크를 되돌리고 raise.
  - `create_symlink`: §D 매핑 후 `create_link`와 같은 코드.
  - `remove_symlink`: dst 없음 → 성공(no-op). `_is_link`가 아니면 `RuntimeError("not a link: " + dst)`. 링크면 `_link_target`·`_link_kind` 기록 후 `_plat("unlink", dst)`.
  - `copy`: dst가 이미 있으면 `FileExistsError` (중첩 방지).
  - 롤백 `create_link`/`create_symlink`: dst가 `_is_link`면 `_plat("unlink")`; `_backup_path`가 있으면 `os.replace(backup, dst)`; `_prev_link_target`이 있으면 `_plat("link-<kind>", target, dst)`. 롤백 `remove_symlink`: `_link_target`이 있고 dst가 없으면 다시 링크(기존 "수동 복원 필요" 메시지를 대체).
- [ ] **Step 5: 하네스 fixture** — §G `fx_link`, `fx_file_links_supported`, `fx_skip`과 위 게이트.
- [ ] **Step 6: GREEN 확인**

  Run: `bash skills/account-partition/tests/unit/run.sh`
  Expected: `All test files passed.`, exit 0 (이 PC). `SKIP S1`, `SKIP S5`, `SKIP R1`, `SKIP E-03`(macOS에서는 E-03만 실행) 줄 출력.
  Run: `bash skills/account-partition/tests/unit/check_assertions_unchanged.sh ca598df`
  Expected: exit 0

- [ ] **Step 7: Commit** — `git commit -m "feat(v0.5-2): platform.sh 링크 계층 — junction 생성·판정·제거, create_link op"`

## Task 3: 삭제 규칙 [TDD]

**Files:**
- Modify: `scripts/platform.sh` (+ `ap_unlink_under`, CLI `unlink-under`)
- Modify: `scripts/plan-execute.sh` (`remove_dir`:70-71, `archive_dir`:167-187), `scripts/plan-rollback.sh` (`copy`:64-67, `archive_dir`:105-121, `remove_dir` 신규), `scripts/plan-build.sh` (입력 끝 `/` 제거)
- Create: `tests/unit/engine_delete_test.sh`, `tests/unit/engine_rules_test.sh`
- Modify: `tests/preconditions.md` 검증 3 표 (junction 제거 두 경우)

**Interfaces:**
- Consumes: Task 2 `ap_unlink`, `ap_link_dir`, `_plat`, `_is_link`, `_no_trailing`
- Produces: `_safe_rmtree(p)`(= `_no_trailing` → p가 링크면 `_plat("unlink")`만 → 아니면 `_plat("unlink-under", p)` 후 `shutil.rmtree(p)`), 메타 `_links`, 사이드카 `<archive>.links.json` (`[{"rel": "plugins", "target": "C:/.../.claude-shared/plugins", "kind": "dir"}]`)

- [ ] **Step 1: 실패 테스트 작성**

  | ID | 입력 | 단정 |
  |---|---|---|
  | `[D-01]` | config dir 안에 공유 보관소 `plugins`로의 링크 + 실제 파일; `remove_dir` | config dir 없음, 보관소 `plugins` 파일 수 그대로 |
  | `[D-02]` | `remove_dir`의 `path`가 `.../.claude-x/` | exit 2, `_error`에 `trailing slash refused`, 디렉토리와 보관소 그대로 |
  | `[D-03]` | 링크가 든 디렉토리에 `archive_dir` | 아카이브 1개; `_links`에 `{"rel":"plugins","kind":"dir"}`; 사이드카 존재; 아카이브 목록(`tarfile`로 읽음)에 보관소 안 파일 이름 없음 |
  | `[D-04]` | `archive_dir` → `remove_dir` → 실패하는 op → 롤백 | config dir 복원, `plugins`가 다시 링크(대상 = 보관소), 보관소 그대로 |
  | `[D-05]` | `plan-build.sh add --config-dir "$X/.claude-a/" --shared-pool "$X/.claude-shared/"` | JSON의 모든 경로가 `/`로 끝나지 않음 |
  | `[D-06]` | `remove_dir`의 path 자체가 링크 | 링크만 사라지고 대상 그대로 |
  | `[R-01]` | `plan-execute.sh`, `plan-rollback.sh` 본문 | `rm -rf`, `"rm", "-rf"` 0건 |
  | `[R-02]` | 같은 두 파일 | `os.symlink(` 0건, `["bash"`·`["tar"` 0건 |
  | `[R-03]` | `scripts/*.sh` (platform.sh 제외) | 실행 코드의 `ln -s` 0건 (`plan-shell-out.sh`가 출력하는 문자열 리터럴은 `print(` 줄이므로 제외 규칙: `print(`가 있는 줄은 세지 않음) |

- [ ] **Step 2: RED** — Run: `bash skills/account-partition/tests/unit/engine_delete_test.sh` → FAIL `[D-01]` 보관소 파일 수(Windows: 기존 `rm -rf`는 대상을 보존하므로 `[D-01]`은 통과할 수 있다 — 이 경우 RED는 `[D-02]`가 exit 0으로 실패, `[D-03]` `_links` 없음으로 확인). Run: `bash skills/account-partition/tests/unit/engine_rules_test.sh` → FAIL `[R-01]` (`plan-execute.sh:71` `rm -rf`).
- [ ] **Step 3: 구현**
  - `remove_dir`: `_safe_rmtree(path)`, 제거한 링크 목록을 `_links`로.
  - `archive_dir`: `_no_trailing(src)` → `_plat("unlink-under", src)` 출력으로 `_links` 작성 → 기존 tar·무결성·rename(`AP_TAR`) → 사이드카 JSON 저장 → `_archive_path`.
  - 롤백 `archive_dir`: src가 없을 때만 아카이브를 푼다(있으면 건너뜀, 덮어쓰지 않음) → `_links` 각 항목에 대해 경로가 없거나 링크 아닌 사본이면 사본을 `_safe_rmtree`로 지우고 `_plat("link-<kind>", target, src/rel)`. 롤백 `remove_dir`: "archive_dir 롤백이 복원" 출력. 롤백 `copy`: `_safe_rmtree(dst)`.
  - `plan-build.sh`: `--config-dir`, `--shared-pool`, `--shell-rc` 값의 끝 `/`를 bash에서 제거(`${v%/}` 반복) 후 `ap_path_native`.
- [ ] **Step 4: 문서** — `tests/preconditions.md` 검증 3의 "적대적 리뷰 후 추가로 재현한 것" 표에 두 줄: `cmd /c rmdir <junction>` → junction만 제거, 대상 보존 / `ap_unlink <junction>/` → 거부(exit 1), junction·대상 보존. 근거는 `[W-05]`·`[W-06]`.
- [ ] **Step 5: GREEN** — Run: `bash skills/account-partition/tests/unit/run.sh` → exit 0.
- [ ] **Step 6: Commit** — `git commit -m "fix(v0.5-3): 삭제 규칙 — 끝 / 거부, 링크 먼저 unlink, 아카이브 복원 후 링크 재생성"`

## Task 4: 환경 감지와 환경 파일 [TDD]

**Files:**
- Modify: `scripts/platform.sh` (+ `ap_python_ok`, `ap_ps_eval`, `ap_env_detect`, `ap_shell_rc`; CLI `detect`, `env-check`, `env-save`, `env-summary`, `shell-rc`, `block-file`, `record-block`, `forget-block`)
- Create: `tests/unit/env_test.sh`; Modify: `platform_windows_test.sh`

**Interfaces:**
- Consumes: Task 2 `ap_link_method`, `ap_devmode`
- Produces: §C 스키마와 CLI 계약, 테스트 주입 `AP_TEST_MODE=1` + `AP_DETECT_FIXTURE=<json 파일>`, `AP_ENV_FILE`, `AP_PYTHON`

- [ ] **Step 1: 실패 테스트 작성** (`env_test.sh`는 fixture로 모든 host에서 돈다)

  | ID | 입력 | 단정 |
  |---|---|---|
  | `[V-01]` | 환경 파일 없음, `env-check` | exit 4, `status` = `first` |
  | `[V-02]` | windows fixture(§C 예시, devmode off), `env-save ps51` | 파일의 `detected` = fixture, `choice.shell_target` = `ps51`, `choice.shell_rc` = fixture `shells[0].profile`, `blocks` = `{}` |
  | `[V-03]` | 같은 fixture로 `env-check` | exit 0, `status` = `same` |
  | `[V-04]` | fixture의 `devmode`→`on`, `link_file`→`symlink` | exit 3, `changed` = `["link_file","devmode"]` (§C 순서) |
  | `[V-05]` | fixture에 `pwsh` 셸 추가 후 `env-save pwsh`, 같은 fixture로 `env-check` | exit 0 (선택은 비교 안 함) |
  | `[V-06]` | `record-block side C:/a/p.ps1 powershell` 후 `env-save ps51` | `block-file side` = `C:/a/p.ps1` |
  | `[V-07]` | `forget-block side` | `block-file side` = `choice.shell_rc` |
  | `[V-08]` | `env-save fish` | exit 2, 파일 바이트 그대로 |
  | `[V-09]` | `AP_PYTHON=<exit 9009 하는 가짜 스크립트>` `env-check` | exit 5, 출력에 `Python` 포함 |
  | `[V-10]` | windows fixture devmode off, `env-summary` | 둘째 줄 = `디렉토리 공유: junction / CLAUDE.md 공유: 안 함 (개발자 모드 꺼짐)`, 첫 줄 = `Windows 11 · PowerShell 5.1 (프로필: C:\Users\gang\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1)` |
  | `[V-11]` | `execution_policy: Restricted` | 출력에 `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
  | `[V-12]` | macos fixture, `env-summary` | `macOS · zsh (~/.zshrc)` / `디렉토리 공유: symlink / CLAUDE.md 공유: symlink` |
  | `[V-13]` | override 모드 `detect` | exit 64 |
  | `[W-12]` | windows 실제 `detect` | `os`=windows, `shells[0].id`=ps51, `shells[0].profile` = `cygpath -m "$(powershell -NoProfile -Command '$PROFILE')"`(CR 제거), `link_dir`=junction, `devmode` = `platform.sh devmode` |
  | `[W-14]` | `ap_ps_eval powershell "Write-Output 'C:\Users\x\OneDrive\문서'"` | 출력이 UTF-8 `C:\Users\x\OneDrive\문서`와 바이트 일치 (F7) |

- [ ] **Step 2: RED** — Run: `bash skills/account-partition/tests/unit/env_test.sh` → FAIL `[V-01]` (`env-check` 미정의, exit 1 ≠ 4).
- [ ] **Step 3: 구현** — §A·§B·§C 규칙 그대로. JSON 처리는 Python(`ap_python_ok` 통과 후에만). `env-check`는 `ap_python_ok` 실패 시 Python 없이 한국어 한 줄: `Python 3.8 이상이 필요합니다. https://www.python.org/downloads/ 에서 설치한 뒤 다시 실행하세요. (Microsoft Store 바로가기 python3는 동작하지 않습니다)`.
- [ ] **Step 4: GREEN** — Run: `bash skills/account-partition/tests/unit/run.sh` → exit 0.
- [ ] **Step 5: Commit** — `git commit -m "feat(v0.5-4): 환경 감지·환경 파일 — 감지 스냅샷/사용자 선택/계정별 블록 파일 분리"`

## Task 5: PowerShell 프로필 편집 [TDD]

**Files:**
- Modify: `scripts/shell-rc.sh` (`.ps1` 분기, `encoding`, `write-block`, `render --format`)
- Modify: `scripts/plan-execute.sh` (`append_block`:98-113, `remove_block`:137-165), `scripts/plan-rollback.sh` (`append_block`:73-98)
- Create: `tests/unit/shell_rc_ps_test.sh`
- Modify: `references/shell-integration.md` (PowerShell 절: 대상 파일, 블록 형식 §E, 인코딩 규칙, UTF-16 수동, 끝 마커 없음 처리)

**Interfaces:**
- Consumes: Task 4 `record-block`/`forget-block`, §E 마커
- Produces:
  - `shell-rc.sh encoding <rc>` → `absent` | `utf-8` | `utf-8-bom` | `utf-16-le` | `utf-16-be` | `legacy`(BOM 없고 UTF-8로 안 읽힘)
  - `shell-rc.sh write-block <rc> <name>` (stdin = 마커 포함 블록 전체) → exit 0 / 3 UTF-16(파일 불변) / 4 시작 마커는 있는데 끝 마커 없음(파일 불변)
  - `shell-rc.sh add|remove|list <rc> ...` — `.ps1`이면 PowerShell 규칙, 아니면 기존 동작 그대로. `remove`의 exit 3·4는 `write-block`과 같음
  - `shell-rc.sh render <name> <config_dir> [--format zsh|powershell]` (기본 zsh = 기존 출력)
  - 실행 엔진: `append_block`·`remove_block` 성공 시 `_plat("record-block"|"forget-block", name, file, format)`

- [ ] **Step 1: 실패 테스트 작성**

  | ID | 입력 | 단정 |
  |---|---|---|
  | `[H-01]` | 없는 `$sb/Documents/WindowsPowerShell/p.ps1`에 `add p.ps1 side "$HOME/.claude-side"` | 디렉토리·파일 생성; 첫 3바이트 ≠ `EF BB BF`; 모든 줄 끝 `\r\n`; 내용 = §E PowerShell 블록 |
  | `[H-02]` | UTF-8 BOM + CRLF + 기존 줄 2개 | BOM 유지, 기존 줄 바이트 그대로, 블록이 CRLF로 끝에 붙음 |
  | `[H-03]` | BOM 없는 UTF-8 + CRLF + 한글 주석(이 PC 프로필 형식, F8) | 한글 주석 바이트 그대로, 블록 CRLF |
  | `[H-04]` | LF만 있는 `.ps1` | 블록도 LF |
  | `[H-05]` | UTF-16 LE BOM 프로필 | `add` exit 3, 파일 sha256 그대로 |
  | `[H-06]` | 같은 이름 `add` 두 번 | 블록 1개, 줄 수 동일(멱등) |
  | `[H-07]` | 블록 2개(side, work) 중 `remove side` | side 시작~끝 마커 포함 전부 제거, work 블록·나머지 바이트 그대로 |
  | `[H-08]` | 마커 없는 `function claude-work { ... }`(F8 원문) 옆에 side 블록, `remove work` / `remove side` | `remove work`: 파일 sha256 그대로; `remove side`: 수동 함수 줄 그대로 |
  | `[H-09]` | 시작 마커만 있고 끝 마커 없음, `remove side` | exit 4, 파일 그대로 |
  | `[H-10]` | cp949로 된 BOM 없는 파일(바이트 `b9 ae bc ad` 포함) | `encoding` = `legacy`; `add` 후 기존 바이트 그대로 + ASCII 블록 |
  | `[H-11]` | `list` (H-08 파일) | `side:managed`, `work:external` |
  | `[H-12]` | 실행 엔진 `append_block {format: powershell}` 성공 → `remove_block` 성공 | 각각 후에 `block-file side` = 그 파일 / `choice.shell_rc` |
  | `[H-13]` | `append_block`이 UTF-16 파일 대상 | 실행 exit 2, `_error`에 `utf-16`, 파일 sha256 그대로 |

- [ ] **Step 2: RED** — Run: `bash skills/account-partition/tests/unit/shell_rc_ps_test.sh` → FAIL `[H-01]` (`.ps1`에도 zsh alias 줄이 써짐).
- [ ] **Step 3: 구현** — `.ps1` 편집은 Python **바이트 단위**: BOM 판정 → UTF-16이면 exit 3 → 줄바꿈 판정(`\r\n` 있으면 CRLF, `\n`만 있으면 LF, 빈/새 파일은 CRLF) → 기존 같은 이름 블록을 시작~끝 마커로 제거(끝 없음 → exit 4) → 파일 끝이 줄바꿈이 아니면 줄바꿈 추가 → ASCII 블록 추가 → 임시 파일 후 `os.replace`. 마커 비교는 줄 단위 `strip()` 후 ASCII 바이트 정확 일치(cp949 2바이트 안에 마커가 끼일 수 없음). zsh 경로는 `shell-rc.sh:43-113` 그대로.
  - 실행 엔진 `append_block`: 백업(`cp -p`) 후 `[AP_BASH, shell-rc.sh, "write-block", file, name]`에 `marker`+`lines`+`end_marker`(있으면)를 `\n`으로 이어 stdin 전달. exit ≠ 0이면 `RuntimeError("append_block: utf-16 profile — manual" | "... end marker missing")`. 실행 엔진은 셸 파일을 직접 `open()`하지 않는다.
  - `remove_block`: `[AP_BASH, shell-rc.sh, "remove", file, name]`. `shell-rc.sh`가 없을 때의 2줄 fallback(`plan-execute.sh:148-165`, `plan-rollback.sh:81-98`)을 지우고 `RuntimeError("shell-rc.sh missing")`.
- [ ] **Step 4: GREEN** — Run: `bash skills/account-partition/tests/unit/run.sh` → exit 0 (`shell_rc_test.sh` 14/14 유지).
- [ ] **Step 5: Commit** — `git commit -m "feat(v0.5-5): PowerShell 프로필 편집 — 인코딩·CRLF 보존, 시작·끝 마커 파서, UTF-16 수동"`

## Task 6: plan 빌드·렌더·드라이런의 OS 분기 [TDD]

**Files:**
- Modify: `scripts/platform.sh` (+ `ap_alias_block`, CLI `alias-block`)
- Modify: `scripts/plan-build.sh:5-159`, `scripts/plan-render.sh:47-79`, `scripts/plan-shell-out.sh:28-77`
- Create: `tests/unit/plan_build_os_test.sh`; Modify: `platform_test.sh`, `plan_build_test.sh`·`plan_render_test.sh`·`plan_shell_out_test.sh` (override 한 줄)

**Interfaces:**
- Consumes: Task 2 `ap_link_method`, Task 4 `block-file`, Task 5 `.ps1` 판정 규칙
- Produces: §D op를 만드는 `plan-build.sh` (인자 목록 변경 없음), `ap_alias_block`

- [ ] **Step 1: 실패 테스트 작성**

  | ID | 입력 | 단정 |
  |---|---|---|
  | `[P-07]` | `AP_OS_OVERRIDE=macos HOME=/Users/test alias-block side /Users/test/.claude-side zsh` | 정확히 2줄 §E zsh |
  | `[P-08]` | `AP_OS_OVERRIDE=windows HOME=/Users/test alias-block side /Users/test/.claude-side powershell` | 정확히 12줄 §E PowerShell (`"$env:USERPROFILE\.claude-side"`) |
  | `[P-09]` | powershell, config dir `D:/claude/.claude-x`(HOME 밖) / `D:/클로드/.claude-x` | `$env:CLAUDE_CONFIG_DIR = "D:\claude\.claude-x"` / exit 3 |
  | `[P-10]` | `HOME=/c/Users/홍길동`, config `/c/Users/홍길동/.claude-side`, powershell | exit 0, 출력 전 바이트 < 0x80 |
  | `[B-01]` | `AP_OS_OVERRIDE=macos HOME=/Users/test plan-build add ... --shell-rc /Users/test/.zshrc --shell-mode auto --shared plugins,CLAUDE.md` | ops = `create_dir /Users/test/.claude-side 0700`, `create_dir /Users/test/.claude-shared 0755`, `create_dir .../plugins 0755`, `create_link {kind dir, method symlink, src .../.claude-shared/plugins, dst .../.claude-side/plugins, backup_if_exists true}`, `create_link {kind file, method symlink, ...CLAUDE.md}`, `append_block {file /Users/test/.zshrc, format zsh, marker "# account-partition: side", lines ["alias claude-side=\"CLAUDE_CONFIG_DIR=$HOME/.claude-side command claude\""], backup true, name side}` — 정확히 이 순서·값; `metadata.os` = macos; `skipped` 없음 |
  | `[B-02]` | `AP_OS_OVERRIDE=windows AP_DEVMODE_OVERRIDE=off`, `--shell-rc .../p.ps1`, `--shared plugins,CLAUDE.md` | `create_link {kind dir, method junction}` 1개, CLAUDE.md 링크 op 없음, `metadata.skipped` = `[{"item":"CLAUDE.md","reason":"file_link_unavailable"}]`, `append_block.format` = powershell, `end_marker` = `# /account-partition: side`, `lines` = §E 함수 본문 10줄 |
  | `[B-03]` | 위와 같고 `AP_DEVMODE_OVERRIDE=on` | CLAUDE.md `create_link {kind file, method symlink}` |
  | `[B-04]` | windows `unlink --shell-rc .../p.ps1 --shell-mode auto` | `remove_block {format powershell, end_marker ...}` |
  | `[B-05]` | windows `edit --add-shared CLAUDE.md` devmode off | CLAUDE.md의 `quarantine`·`create_link` 없음, `skipped`에 CLAUDE.md |
  | `[B-06]` | `plan-render` of `[B-02]` plan | `건너뜀     글로벌 인스트럭션 — 개발자 모드가 꺼져 있어 계정마다 따로 씁니다` 줄, 플러그인 줄 끝 `(junction)` |
  | `[B-07]` | `plan-shell-out` of `[B-02]` plan | `MSYS2_ARG_CONV_EXCL='*' cmd /c mklink /J 'C:\...\plugins' 'C:\...\plugins'`(백슬래시 형식) 포함, `ln -s` 없음, `bash "$SCRIPTS/shell-rc.sh" add` 포함 |
  | `[B-08]` | `plan-shell-out` of windows unlink plan | `bash "$SCRIPTS/platform.sh" unlink-under`, `tar --force-local czf` 포함, `rm -rf` 인자가 `/`로 끝나지 않음 |

  기존 텍스트 생성 테스트 3개(`plan_build_test.sh`, `plan_render_test.sh`, `plan_shell_out_test.sh`)는 `source assert.sh` 다음 줄에 `export AP_OS_OVERRIDE=macos`만 더한다(assert 줄 불변). 이유: 이 PC(개발자 모드 꺼짐)에서 `plan_build_test.sh:58-64`의 `--add-shared CLAUDE.md`가 `quarantine`을 만들지 않게 되어 `:61` assert가 깨지므로, 이 세 파일을 macOS 출력 회귀 가드로 고정한다. 부수 효과로 `plan_build_test.sh`의 경로 assert가 MSYS 변환 결과의 부분 문자열이 아니라 `/Users/test/...` 그대로를 단정하게 된다.

- [ ] **Step 2: RED** — Run: `bash skills/account-partition/tests/unit/plan_build_os_test.sh` → FAIL `[B-01]` (`create_symlink` ≠ `create_link`).
- [ ] **Step 3: 구현**
  - `plan-build.sh`: bash에서 `ap_os`, `ap_link_method dir|file`, `ap_alias_block`(형식은 `--shell-rc` 확장자)를 계산해 env(JSON 문자열)로 Python에 넘긴다. `metadata.os`, `skipped`. `edit`의 `add_shared`에서 file 항목이 `none`이면 `quarantine`도 만들지 않는다. `remove_shared`는 기존 그대로 `remove_symlink` + `copy`.
  - `plan-render.sh`: `create_link`는 기존 `create_symlink` 줄 형식 + method가 junction이면 ` (junction)`. 구 `create_symlink` 줄은 바이트 그대로. `metadata.skipped` 줄.
  - `plan-shell-out.sh`: `metadata.os`(없으면 macos)가 windows일 때만 새 문자열(`[B-07]`·`[B-08]`, `remove_symlink` → `bash "$SCRIPTS/platform.sh" unlink '<dst>'`, file symlink → `MSYS=winsymlinks:nativestrict ln -s`). macos·구 plan 출력은 바이트 그대로.
- [ ] **Step 4: GREEN** — Run: `bash skills/account-partition/tests/unit/run.sh` → exit 0 (`plan_build_test.sh` 25/25, `plan_render_test.sh` 17/17, `plan_shell_out_test.sh` 19/19 유지).
- [ ] **Step 5: Commit** — `git commit -m "feat(v0.5-6): plan OS 분기 — create_link kind/method, PowerShell 블록, CLAUDE.md 생략"`

## Task 7: 6개 sub-skill + 메뉴의 환경 확인 단계 (§21.1) [Manual + 문서 계약 테스트]

**Files:**
- Create: `skills/account-partition/references/env-check.md`, `tests/unit/docs_contract_test.sh`
- Modify: `skills/{account-partition,add,list,edit,login,logout,unlink}/SKILL.md`

**Interfaces:**
- Consumes: Task 4 CLI `env-check`/`env-save`/`env-summary`/`shell-rc`/`block-file`, Task 2 `link-method`
- Produces: 각 SKILL의 `### Step 0. 환경 확인` (이후 단계가 쓰는 변수: `RC`(셸 통합 파일, 수동이면 빈 값), `AP_OSN`(`platform.sh os`))

- [ ] **Step 1: 실패 테스트 작성** — `docs_contract_test.sh`

  | ID | 단정 |
  |---|---|
  | `[C-01]` | 7개 SKILL.md 모두 `### Step 0. 환경 확인`과 `platform.sh" env-check`, `references/env-check.md`를 포함 |
  | `[C-02]` | `references/env-check.md`에 질문 원문 `이 환경으로 진행할게요. 맞나요?`와 선택지 `맞아요`, `개발자 모드를 켜고 다시 확인할게요`, `셸 통합 대상을 바꿀게요`, `취소`, exit 코드 0/3/4/5 분기 표 |
  | `[C-03]` | 7개 SKILL.md 어디에도 `list ~/.zshrc`, `--shell-rc "$HOME/.zshrc"` 없음 |

- [ ] **Step 2: RED** — Run: `bash skills/account-partition/tests/unit/docs_contract_test.sh` → FAIL `[C-01]` (add/SKILL.md에 Step 0 없음).
- [ ] **Step 3: 작성**
  - `references/env-check.md`: exit 0 → `env-summary` 한 줄 요약만 보여 주고 진행(질문 없음). exit 4 → `env-summary`를 본문으로 §21.1 질문. exit 3 → `changed` 항목만 "바뀐 항목: 개발자 모드(꺼짐→켜짐)" 형식으로 보여 주고 같은 질문. exit 5 → 안내 출력 후 중단. 선택지: `맞아요` → `env-save <현재 shell_target, 첫 실행이면 shells[0].id, 없으면 manual>`; `개발자 모드를 켜고 다시 확인할게요`(windows이고 devmode off일 때만) → 켜는 법(Windows 11: 설정 > 시스템 > 개발자용 > 개발자 모드, Windows 10: 설정 > 업데이트 및 보안 > 개발자용) 출력 후 `env-check` 재실행; `셸 통합 대상을 바꿀게요` → 두 번째 질문(감지된 다른 셸 + `수동 안내`) → `env-save <id|manual>`; `취소` → 종료.
  - 각 SKILL.md: "Scripts 위치 찾기" 다음에 Step 0 (명령 3줄 + reference 지시). Bash 호출마다 셸 상태가 이어지지 않으므로 이후 단계 코드 블록은 각자 `RC=$(bash "$SCRIPTS/platform.sh" shell-rc)`를 다시 구한다. `~/.zshrc` 하드코딩을 `$RC`로: add Step 1 충돌 검사·Step 4 질문 문구("셸 통합 파일(`<RC>`)에 명령어를 어떻게 추가할까요?")·Step 6 `--shell-rc "$RC"`·Step 9 안내(windows: "새 PowerShell 창을 여세요", macos: 기존 문구), edit Step 1, unlink Step 1(`list "$RC"`)과 Step 3(`--shell-rc "$(bash "$SCRIPTS/platform.sh" block-file <name>)"`), Step 7 결과 문구. `RC`가 비면(수동) add는 `--shell-mode manual`만 제시.
  - 메뉴(`account-partition/SKILL.md`): Step 0을 메뉴보다 먼저. 메뉴의 "v1 미지원, 안내만" 문구 제거, login/logout 메뉴 항목 추가(sub-skill 6개와 일치).
- [ ] **Step 4: GREEN** — Run: `bash skills/account-partition/tests/unit/docs_contract_test.sh` → exit 0.
- [ ] **Step 5: Commit** — `git commit -m "feat(v0.5-7): 모든 sub-skill 첫 단계에 환경 확인 — 감지·확인·저장"`

## Task 8: 외부 계정 인식과 경로 정규화 (§21.4) [TDD]

**Files:**
- Modify: `scripts/shell-rc.sh` (+ `list-detail`), `scripts/discover.sh` (+ `list-dirs --no-default`, `item-state`, `accounts`, `auth-status`, `present-items`), `scripts/matrix.sh`
- Create: `tests/unit/discover_ext_test.sh`
- Modify: `skills/{login,logout,edit,unlink,list}/SKILL.md`, `tests/unit/docs_contract_test.sh` (+ `[C-04]`)

**Interfaces:**
- Consumes: Task 1 `ap_path_key`, Task 2 `ap_is_link`/`ap_link_target`, Task 4 환경 파일(`detected.shells[].profile`, `choice.shell_rc`), Task 6 `ap_link_method`
- Produces:
  - `shell-rc.sh list-detail <rc>` → JSON 한 줄씩 `{"name","source":"managed"|"external","fn","config_dir"(native),"key","restores_env":true|false|null,"format"}`. PowerShell: `function <fn> {`부터 중괄호 짝까지 본문에서 `$env:CLAUDE_CONFIG_DIR = "<v>"|'<v>'`를 찾는다. `$env:USERPROFILE`·`${env:USERPROFILE}`·`$HOME`·앞의 `~`를 HOME(native)으로, `\`→`/`. `name` = `fn`에서 앞 `claude-` 제거. `restores_env` = 본문에 `finally`가 있고 `$prev` 또는 `Remove-Item Env:CLAUDE_CONFIG_DIR`가 있으면 true. zsh alias: `CLAUDE_CONFIG_DIR=([^ "]+)`, `restores_env: null`
  - `discover.sh accounts` → JSON 한 줄씩 `{"key","dir","alias","email","has_dir","rc_source":"managed"|"external"|"none","rc_file","restores_env"}`. rc 파일 목록 = `AP_RC_FILES`(줄바꿈 구분, 테스트용) 또는 환경 파일의 `detected.shells[].profile` ∪ `choice.shell_rc`. 디렉토리와 함수는 `key`로 합친다
  - `discover.sh list-dirs --no-default` (default `~/.claude`를 키 비교로 제외), `discover.sh item-state <config_dir> <item>` → `shared` | `external <target>` | `isolated` | `absent`, `discover.sh auth-status <dir>` → `✓ <email>` | `— (로그인 안 됨)` | `— (확인 실패)`, `discover.sh present-items` → 계정 디렉토리·보관소 어디든 있는 항목 id를 `plugins skills commands agents CLAUDE.md` 순서로 한 줄씩

- [ ] **Step 1: 실패 테스트 작성** — fixture: 샌드박스 HOME에 `.claude`(plugins·skills·commands), `.claude-work`·`.claude-dami`(각 `.claude.json`, `plugins`·`skills`·`commands`를 `fx_link`로 `.claude/<item>`에), 프로필 `.ps1`에 F8의 두 함수 원문(`$env:CLAUDE_PROFILE` 줄 포함) + 스킬 블록 `side` + `.claude-side`(보관소 링크).

  | ID | 단정 |
  |---|---|
  | `[X-01]` | `list-detail`: `work` external `restores_env:false` `config_dir` = `<HOME native>/.claude-work`; `side` managed `restores_env:true` |
  | `[X-02]` | `accounts`: `work`·`dami` 각각 정확히 1행(디렉토리 행과 함수 행이 키로 합쳐짐), `rc_source:external` |
  | `[X-03]` | 함수만 있고 디렉토리 없는 `ghost` → `has_dir:false`; `.claude-old`(함수 없음, `.claude.json` 있음) → `rc_source:none` |
  | `[X-04]` | `item-state .claude-work plugins` = `external <HOME native>/.claude/plugins`; `.claude-side plugins` = `shared` |
  | `[X-05]` | `matrix.sh` 출력: `※ claude-work 플러그인: 공유 (외부: ~/.claude 직결)`, `⚠ 이 함수를 실행한 창에서는 \`claude\`가 이 계정으로 뜹니다` (work 행), `⚠ 부분 등록 — alias만 있음 (디렉토리 없음)` (ghost) |
  | `[X-06]` | windows+`AP_DEVMODE_OVERRIDE=off`, `.claude-work/CLAUDE.md` 실제 파일 → 매트릭스 글로벌 인스트럭션 셀 `공유 안 됨`, 각주 `※ 글로벌 인스트럭션(CLAUDE.md)은 개발자 모드가 꺼져 있어 계정마다 따로 씁니다. 켜는 법: 설정 > 시스템 > 개발자용 > 개발자 모드` |
  | `[X-07]` | `list-dirs --no-default`에 `.claude` 없음, `list-dirs`에는 있음 |
  | `[X-08]` | 작업 전후 프로필 sha256·`.claude-work/plugins` 링크 대상 동일 (조회는 읽기 전용) |
  | `[C-04]` | login/logout/edit/unlink SKILL.md에 `[ "$d" = "$HOME/.claude" ]`와 인라인 `python3 -c` 없음, `list-dirs --no-default`·`auth-status` 사용 |

- [ ] **Step 2: RED** — Run: `bash skills/account-partition/tests/unit/discover_ext_test.sh` → FAIL `[X-01]` (`list-detail` 미정의).
- [ ] **Step 3: 구현** — 위 Produces 그대로. `matrix.sh`는 계정 목록을 `discover.sh accounts`에서 얻고, 셀 판정에 `item-state`와 같은 규칙(§F `_is_link`·`_link_target`·`_key`)을 쓴다. 외부 링크 셀 = `공유(외부)`, 대상이 `<HOME>/.claude/<item>`이면 각주 `(외부: ~/.claude 직결)`, 아니면 `(외부: <~로 줄인 대상>)`. 기존 `링크→외부`(`matrix.sh:133`) 대체. 범례에 `공유(외부)`·`공유 안 됨` 두 줄 추가. SKILL 수정: login/logout Step 1 루프를 `list-dirs --no-default` + `auth-status`로, edit Step 2·3의 `readlink` 비교를 `item-state`로, list에 "외부 계정은 수정·해제를 수동 안내로만 한다" 문장.
- [ ] **Step 4: GREEN** — Run: `bash skills/account-partition/tests/unit/run.sh` → exit 0 (`matrix_test.sh` 11/11, `discover_test.sh` 8/8 유지).
- [ ] **Step 5: Commit** — `git commit -m "feat(v0.5-8): 외부 계정 인식 — PowerShell 함수 발견·키 정규화·환경변수 미복원 경고"`

## Task 9: 마켓플레이스 주소 대조 (§21.5) [TDD]

**Files:**
- Create: `scripts/marketplace.sh`, `tests/unit/marketplace_test.sh`
- Modify: `scripts/matrix.sh` (경고 절), `skills/list/SKILL.md` (해결 안내)

**Interfaces:**
- Consumes: Task 8 `discover.sh accounts`
- Produces: `marketplace.sh check <config_dir>` → 불일치마다 TAB 구분 한 줄 `<이름>\t<공유 주소>\t<계정 주소>`, exit 0(불일치 유무와 무관), 파일 파싱 실패 시 stderr 경고 + exit 0. 주소 = `source.repo`(github) | `source.url`(git/url) | `source.path`(directory). 비교는 앞뒤 공백 제거·소문자. 공유 쪽 = `<config_dir>/plugins/known_marketplaces.json`(링크를 따라 읽음), 계정 쪽 = `<config_dir>/settings.json`의 `extraKnownMarketplaces`. 양쪽에 모두 있는 이름만 비교. `settings.json`은 `extraKnownMarketplaces` 외 키를 읽지도 출력하지도 않는다

- [ ] **Step 1: 실패 테스트 작성**

  | ID | 입력 | 단정 |
  |---|---|---|
  | `[M-01]` | 공유 `superpowers-dev` repo `glaude-skills/superpowers`, 계정 `gang/superpowers` | 한 줄 `superpowers-dev\tglaude-skills/superpowers\tgang/superpowers` |
  | `[M-02]` | 같은 주소(대소문자만 다름) | 출력 없음 |
  | `[M-03]` | 계정 쪽에만 있는 이름, 공유 쪽에만 있는 이름 | 출력 없음 |
  | `[M-04]` | `settings.json`에 `"apiKey": "sk-secret"` 포함 | 어떤 출력에도 `sk-secret` 없음 |
  | `[M-05]` | 깨진 `settings.json` | exit 0, stdout 없음 |
  | `[M-06]` | `matrix.sh`(M-01 fixture) | `⚠ 마켓플레이스 주소 불일치: \`superpowers-dev\` 공유=\`glaude-skills/superpowers\`, 이 계정=\`gang/superpowers\`. 이 계정에서 플러그인이 꺼집니다` 줄과 바로 아래 `  해결: <dir>/settings.json 의 extraKnownMarketplaces.superpowers-dev.source.repo 를 "glaude-skills/superpowers" 로 바꾸세요` |

- [ ] **Step 2: RED** — Run: `bash skills/account-partition/tests/unit/marketplace_test.sh` → FAIL `[M-01]` (스크립트 없음이 아니라 `marketplace.sh`를 `exit 0`만 하는 빈 스크립트로 먼저 두고 출력 없음으로 실패 확인).
- [ ] **Step 3: 구현** — 위 Produces. 해결 안내의 키 이름은 주소 종류(`repo`/`url`/`path`)를 따른다.
- [ ] **Step 4: GREEN** — Run: `bash skills/account-partition/tests/unit/run.sh` → exit 0.
- [ ] **Step 5: Commit** — `git commit -m "feat(v0.5-9): 조회에 마켓플레이스 주소 대조 — 불일치 경고와 수동 수정 안내"`

## Task 10: 활성 세션 게이트 (§21.8) [TDD]

**Files:**
- Modify: `scripts/platform.sh` (+ `ap_check_active`, CLI `check-active`), `scripts/safety.sh:73-107` (`check-active` → `ap_check_active` 위임)
- Modify: `tests/unit/safety_test.sh:69-77` (fixture만: `$$` → `$(fx_native_pid)`), 새 assert 추가
- Modify: `design.md` §11 활성 세션 게이트(한계 명시), `skills/{add,edit,unlink,login,logout}/SKILL.md` (경고 출력 처리)

**Interfaces:**
- Consumes: Task 1 `ap_host_os`, §G `fx_native_pid`
- Produces: `ap_check_active <config_dir>` — host=windows: ① `<dir>/.account-partition.lock`의 PID가 `kill -0`로 살아 있으면 `Active account-partition run: PID <p>` exit 0 ② `<dir>/daemon.lock`이 있고 PID(순서: `daemon.status.json.pid` → `daemon.lock.pid`(JSON) → `daemon.status.json.supervisorPid`)가 `MSYS2_ARG_CONV_EXCL='*' tasklist /FI "PID eq <pid>" /NH /FO CSV` 출력에 `"<pid>"`로 있으면 `Active daemon: PID <pid> (config: <dir>)` exit 0 ③ 아니면 `tasklist /FI "IMAGENAME eq claude.exe" /NH /FO CSV`의 `"claude.exe"` 줄 수에서 1(이 세션)을 뺀 N이 1 이상이면 `경고: 다른 Claude 창이 N개 떠 있습니다. 대상 계정을 쓰는 창이면 닫고 진행하세요.` 출력, exit 1. host≠windows: 기존 본문 그대로

- [ ] **Step 1: 실패 테스트 작성** (`[S-*]`는 `fx_windows_only` 블록 안 — 파일 전체를 건너뛰지 않도록 `if host=windows; then ... fi`)

  | ID | 입력 | 단정 |
  |---|---|---|
  | `[S-01]` | `daemon.lock` = `{"pid": <fx_native_pid>}`, status 없음 | exit 0, 출력에 `Active daemon` |
  | `[S-02]` | `daemon.lock` 빈 파일 + `daemon.status.json` = `{"supervisorPid": <fx_native_pid>}` | exit 0 |
  | `[S-03]` | `daemon.lock` = `{"pid": 999999}` | exit 1 |
  | `[S-04]` | `.account-partition.lock` = `$$` | exit 0, `Active account-partition run` |
  | `[S-05]` | PATH 앞에 가짜 `tasklist`(IMAGENAME 질의에 claude.exe CSV 3줄, PID 질의에 일치 없음) | exit 1, 출력에 `다른 Claude 창이 2개 떠 있습니다` |

  기존 `check-active: 활성 daemon 감지` 시나리오는 `daemon.status.json`에 `$(fx_native_pid)`를 쓰도록 fixture만 바꾼다(macOS에서는 `$$`와 같다).

- [ ] **Step 2: RED** — Run: `bash skills/account-partition/tests/unit/safety_test.sh` → FAIL `[S-01]` (status.pid만 읽어 exit 1).
- [ ] **Step 3: 구현** — 위 Produces. macOS·linux 분기는 `safety.sh:73-107` 본문을 바꾸지 않고 옮긴다. SKILL의 게이트 단계: exit 0 → 차단(기존 문구), exit 1이고 `경고:` 줄이 있으면 그 줄을 보여 주고 `AskUserQuestion`(`진행` / `취소`). `design.md` §11 활성 세션 게이트에 "Windows는 다른 프로세스의 환경변수를 읽을 수 없어 lockfile·daemon 마커로만 차단하고 claude.exe 수는 경고만 한다" 한 단락.
- [ ] **Step 4: GREEN** — Run: `bash skills/account-partition/tests/unit/run.sh` → exit 0.
- [ ] **Step 5: Commit** — `git commit -m "feat(v0.5-10): Windows 활성 세션 게이트 — lockfile·daemon 마커 차단, claude.exe 수 경고"`

## Task 11: add Step 2를 항목 직접 선택으로 (D6, §7) [Manual + 문서 계약 테스트]

**Files:**
- Modify: `skills/add/SKILL.md` (Step 2·2a → Step 2 하나), `skills/edit/SKILL.md` (Step 2 토글 선택지 규칙), `references/item-mapping.md` (Windows 파일 공유 규칙), `tests/unit/docs_contract_test.sh` (+ `[C-05]`), `tests/manual.md` MV-1·MV-2·MV-3 절차 문구(프리셋 단계 제거)

**Interfaces:**
- Consumes: Task 8 `discover.sh present-items`, Task 2 `link-method file`
- Produces: add Step 2의 결과 CSV(기존 `--shared` 인자 형식 그대로)

- [ ] **Step 1: 실패 테스트** — `[C-05]`: add/SKILL.md에 `기본 분리`, `거울 모드`, `완전 격리`, `Step 2a` 없음; `다른 계정과 공유할 항목을 골라 주세요. 아무것도 안 고르면 전부 따로 씁니다.`, `플러그인 (추천)`, `스킬 (추천)`, `슬래시 명령 (추천)`, `서브에이전트 (추천)`, `글로벌 인스트럭션(CLAUDE.md)은 개발자 모드가 꺼져 있어 계정마다 따로 씁니다.`, `present-items`, `link-method file` 포함. edit/SKILL.md에 같은 개발자 모드 문장 포함.
- [ ] **Step 2: RED** — Run: `bash skills/account-partition/tests/unit/docs_contract_test.sh` → FAIL `[C-05]` (`기본 분리` 존재).
- [ ] **Step 3: 작성** — §7 질문 원문. 선택지 = `present-items` 결과에서 `link-method file`이 `none`이면 `CLAUDE.md` 제외 + 질문에 그 한 줄. 아무것도 고르지 않으면 `--shared ""`. 선택지가 5개일 때는 DECISION-2 결과를 따른다(기본안: 한 번의 `AskUserQuestion`에 질문 둘 — ① 도구 4개 multiSelect ② `글로벌 인스트럭션(CLAUDE.md)도 공유할까요?` 공유/따로). edit Step 2 토글도 같은 노출 규칙.
- [ ] **Step 4: GREEN** — Run: `bash skills/account-partition/tests/unit/docs_contract_test.sh` → exit 0.
- [ ] **Step 5: Commit** — `git commit -m "feat(v0.5-11): 프리셋 화면 제거 — 공유 항목 직접 선택, 개발자 모드 꺼짐이면 CLAUDE.md 제외"`

## Task 12: 플랫폼 표기·버전 0.5.0·수동 검증 시나리오 (D7) [Manual + 문서 계약 테스트]

**Files:**
- Modify: `README.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `commands/unlink.md`, `commands/account-partition.md`, `tests/manual.md`, `tests/unit/docs_contract_test.sh` (+ `[C-06]`~`[C-09]`), `design.md` §21 "현재 동작" 줄

**Interfaces:**
- Consumes: 앞 task 전부 (문서가 가리키는 명령·문구)
- Produces: 없음

- [ ] **Step 1: 실패 테스트**

  | ID | 단정 |
  |---|---|
  | `[C-06]` | README에 `**플랫폼**: macOS + Windows` 줄, `macOS + zsh (1차)` 없음, Windows 사전 요구(Git for Windows, Python 3.8+, 개발자 모드 선택) 절 |
  | `[C-07]` | 두 json의 `version` = `0.5.0`(Python json 파싱), plugin.json `keywords`에 `windows`, 두 `description`에 `macOS + Windows`, `(macOS+zsh)` 없음 |
  | `[C-08]` | `tests/manual.md`에 `## MV-W1`~`## MV-W9` 9개 제목 |
  | `[C-09]` | `commands/unlink.md`·메뉴 SKILL에 `미지원` 없음 |

- [ ] **Step 2: RED** — Run: `bash skills/account-partition/tests/unit/docs_contract_test.sh` → FAIL `[C-06]`.
- [ ] **Step 3: 작성** — 수동 시나리오(이 PC, 각 시나리오에 기대 결과와 확인 명령):
  - MV-W1 첫 실행 환경 확인: 질문 본문이 `env-summary`와 같고, `맞아요` 후 두 번째 호출은 묻지 않는다.
  - MV-W2 add `test1` (플러그인·스킬): `~/.claude-test1/plugins`가 junction(`fsutil` 태그 `0xa0000003`), 프로필 끝에 §E 블록(CRLF·기존 BOM 여부 유지), 새 PowerShell 창 `claude-test1` 실행 후 종료 → 같은 창에서 `$env:CLAUDE_CONFIG_DIR`이 비어 있음.
  - MV-W3 list: `claude-work`·`claude-dami`가 외부, `공유(외부)` + `~/.claude 직결` 각주, 환경변수 미복원 경고, 마켓플레이스 불일치 줄(있으면).
  - MV-W4 edit `test1` 플러그인 해제: junction 제거, 보관소 `plugins` 파일 수 그대로, `~/.claude-test1/plugins`는 실제 디렉토리.
  - MV-W5 unlink `test1`: 프로필에서 블록만 사라짐(나머지 바이트 동일 — 백업과 `cmp`), 아카이브·사이드카 생성, 보관소 그대로.
  - MV-W6 개발자 모드 켠 뒤 재실행: 바뀐 항목만 보여 주는 확인, add에 글로벌 인스트럭션 선택지 등장, `CLAUDE.md`가 symlink(`0xa000000c`).
  - MV-W7 `claude-test1` 창을 띄운 채 edit: daemon 차단 또는 claude.exe 경고.
  - MV-W8 UTF-16 프로필 사본으로 셸 대상 지정 후 add: 자동 편집 없이 수동 안내 블록 출력, 파일 그대로.
  - MV-W9 전 과정 후 `claude-work`·`claude-dami`: 프로필의 두 함수 줄 바이트 그대로, 두 계정의 junction 대상 그대로(`readlink`), `settings.json` 수정 시각 그대로.
  - 버전 `0.5.0`, README 상태 줄 `v0.5 — ... Windows(Git Bash + PowerShell) 지원`, design §21 "현재 동작" 줄 갱신.
- [ ] **Step 4: GREEN** — Run: `bash skills/account-partition/tests/unit/run.sh` → `All test files passed.`, exit 0. Run: `bash skills/account-partition/tests/unit/check_assertions_unchanged.sh ca598df` → exit 0.
- [ ] **Step 5: Commit** — `git commit -m "chore: version 0.5.0 (Windows 지원 — junction 공유, PowerShell 프로필, 환경 확인)"`

---

## Self-Review

1. **Spec coverage** — D1 → Task 12 MV-W; D2 → Task 1~6(bash 헬퍼 유지, OS 분기만); D3 → Task 2; D4 → Task 2(`link-method file`)·6(`skipped`)·8(`공유 안 됨`)·11; D5 → Task 4·7; D6 → Task 11; D7 → Task 12와 `AP_OS_OVERRIDE=macos` golden(`[B-01]`, `[P-07]`); §21.1 감지 표 각 행 → `[W-12]`·`[V-*]`, 실행 정책 → `[V-11]`, Python 스텁 → `[V-09]`, 저장 3항목 → `[V-02]`·`[V-05]`·`[V-06]`; §21.2 함수 9개 → §A(이름 그대로), `create_link` → Task 2; §21.3 블록 → `[P-08]`, 마커 파서 → Task 5; §21.4 → Task 8; §21.5 → Task 9; §21.6 영향 범위 파일 목록 → File Structure와 일치; §21.7 → `platform_test.sh`(override)·`platform_windows_test.sh`(실제 Windows)·실패 주입 `[W-08]`·`[E-04]`·MV-W9; §21.8 경로 계약 → Task 1, 링크 판정 → Task 1·2(`[E-05]`·`[E-09]` junction 롤백), 삭제 규칙 → Task 3, 프로필 인코딩 → Task 5, 활성 세션 → Task 10, §7 → Task 11. 빈 곳 없음.
2. **Step scan** — "적절히" 류 문장 없음. 구현 본문은 §A·§F 규칙과 테스트 표가 결정하므로 코드 블록은 블록 원문(§E)과 스키마(§C)뿐.
3. **이름 일치** — `create_link`/`remove_symlink`(이름 유지)/`kind`/`method`, `record-block`/`forget-block`/`block-file`, `_is_link`/`_link_target`/`_key`/`_native`/`_no_trailing`/`_plat`/`_safe_rmtree`, `fx_link`/`fx_file_links_supported`/`fx_skip`/`fx_native_pid`/`fx_windows_only`를 Task 1~12에서 같은 철자로 썼다.
4. **Review Focus** — 5줄 각각 테스트를 owning task에 넣었다(`[W-03]`, `[P-10]`, `[W-06]`, `[D-02]`, `[D-05]`, `[H-05]`, `[X-02]`~`[X-05]`, `[H-08]`, `[W-14]`, `[H-01]`).
5. **분량** — 공통 계약을 한 번만 쓰고 task는 테스트 표와 규칙으로만 채웠다.
6. **기존 코드 주장 확인** (열어 본 위치)

| 주장 | 확인 위치 |
|---|---|
| render·shell-out 실패 원인은 stdout cp949 | 실행 traceback(`line 21`, `line 14`), `plan-render.sh:31`, `plan-shell-out.sh:24` |
| matrix가 WSL bash를 부름 | `matrix.sh:35,53`, 실행 출력 `execvpe(/bin/bash)` |
| 롤백 시나리오 1은 거짓 통과 | `plan_rollback_test.sh:14`(`ln -s`), `plan-rollback.sh:51`(`islink` false → 아무것도 안 함), 실행 출력 `rm .../settings.json`만 출력 |
| plan_build 경로 assert는 MSYS 변환을 부분 문자열로 맞힘 | `plan-build.sh:9-11`, 실행 출력 `C:/Program Files/Git/Users/test/.claude-side` |
| 실행 엔진의 `create_symlink`는 `cp -Rp` 후 `rm -rf` | `plan-execute.sh:80-86` |
| `remove_symlink`는 `islink` false면 아무것도 안 함 | `plan-execute.sh:88-90` |
| `remove_dir`는 `rm -rf` | `plan-execute.sh:70-71` |
| `remove_block`·롤백의 2줄 fallback | `plan-execute.sh:148-165`, `plan-rollback.sh:81-98` |
| `append_block`은 파일을 직접 `open(..., "a")` | `plan-execute.sh:110-113` |
| `safety.sh` daemon PID는 `daemon.status.json.pid`만 | `safety.sh:79-93` |
| `discover.sh` default 판정은 문자열 비교 | `discover.sh:29` |
| SKILL의 default 제외는 `[ "$d" = "$HOME/.claude" ]` | `skills/login/SKILL.md:32-34` Step 1 루프 |
| `shell-rc.sh list` 출력 형식 `name:managed|external` | `shell-rc.sh:79-113` |
| 기존 zsh alias의 `$HOME` 치환 | `plan-build.sh:36-45` |
| plan_render·shell_out 테스트는 구 `create_symlink` op를 입력으로 씀 | `plan_render_test.sh:17-18`, `plan_shell_out_test.sh:7` |
| plan_build 테스트는 `remove_symlink` 문자열을 단정 | `plan_build_test.sh:64` |

## 결정이 필요한 것과 가정

- **[DECISION_NEEDED] DECISION-1 백업 파일 0600 (Windows)** — Git Bash `noacl` 마운트에서 `chmod`가 효과 없다(`safety_test.sh:52-53` 실패 원인). 기본안 A: Windows에서는 그 단정을 건너뛰고 §17에 "사용자 프로필 ACL 상속" 주석. 대안 B: `icacls <file> /inheritance:r /grant:r "%USERNAME%:F"`로 소유자 전용 ACL을 걸고 그것을 단정. 계획은 A로 썼다.
- **[DECISION_NEEDED] DECISION-2 선택지 5개** — §7은 5개 선택지를 한 질문에 둔다. `AskUserQuestion`은 질문당 선택지 4개까지다(v0.4 Step 2a도 5개였다). 기본안: 5개일 때 한 호출에 질문 둘(도구 4개 multiSelect + 글로벌 인스트럭션 공유/따로). Windows 개발자 모드 꺼짐은 4개라 해당 없음.
- **[ASSUMPTION]** 개발자 모드가 꺼진 이 PC에서 파일 링크를 요구하는 기존 assert 4개(`plan_execute_test.sh` 시나리오 1)는 통과시킬 수 없다(D4). 원문 블록은 그대로 두고 capability 게이트 + 디렉토리 변형으로 대체한다. 시나리오 5와 롤백 시나리오 1도 같은 게이트(지금의 통과가 거짓 통과라서).
- **[ASSUMPTION]** `AP_OS_OVERRIDE`는 텍스트를 만드는 함수만 바꾼다. override ≠ host이면 경로 변환을 하지 않고 링크·감지 함수는 exit 64로 거부한다.
- **[ASSUMPTION]** op 이름 `remove_symlink`를 유지한다(`plan_build_test.sh:64`가 단정). spec은 `create_symlink`만 이름을 바꾼다.
- **[ASSUMPTION]** Python 판정은 `isjunction` 대신 `st_reparse_tag == 0xA0000003`(3.8+에서 같은 결과). Python 하한 3.8.
- **[ASSUMPTION]** §21.8의 "lockfile"은 `.account-partition.lock`(다른 account-partition 실행)과 `daemon.lock` 둘 다. daemon PID는 F9 때문에 `daemon.lock.pid`·`supervisorPid`로 fallback. macOS 분기는 그대로라 같은 문제가 macOS에 있으면 미해결(P1-2 후보).
- **[ASSUMPTION]** claude.exe 경고의 N = 개수 − 1(이 세션). daemon도 claude.exe라 N이 실제 창 수보다 클 수 있다.
- **[ASSUMPTION]** §21.5 "맞추는 명령"은 `settings.json`의 키와 새 값을 알려 주는 수동 수정 안내다(그 키를 고치는 검증된 CLI가 없다).
- **[ASSUMPTION]** Windows 아카이브는 Git `tar --force-local`(F6). macOS는 기존 `tar` 그대로.
- **[ASSUMPTION]** 환경 확인 질문의 "개발자 모드" 선택지는 Windows + 꺼짐일 때만, "셸 통합 대상을 바꿀게요"는 항상(다른 감지 셸 + 수동 안내).
- **[ASSUMPTION]** 버전은 Task 12에서 한 번 0.5.0으로 올린다. 중간 task는 Windows에서 끝까지 쓸 수 없는 상태라 `/plugin update` 검증 단위가 아니다.
- 범위 밖으로 기록만: F11 `.credentials.json`이 unlink 아카이브에 남을 수 있음, `quarantine` op가 없는 경로에서 `mv` 실패(`plan-execute.sh:115-121`, 기존 동작).
