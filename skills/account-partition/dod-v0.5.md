---
feature: account-partition v0.5 — Windows 지원 (macOS 유지)
slug: v0.5-windows-design
status: DRAFT
frozen_at:
verdict_commit:
source: skills/account-partition/design.md §21 (D1~D7, §21.1~§21.8) + §7, 커밋 ca598df / 2026-10-07 사용자 요청("기존 단위 테스트 57건 실패를 Windows에서 통과", "macOS 회귀 방지")
---

## Scope

**Included**

- `scripts/platform.sh` 신설: OS 판정(`AP_OS_OVERRIDE`), 경로 계약(`cygpath -m`, 계정 키), 링크 생성·판정·제거(junction / symlink), 환경 감지·환경 파일, 셸 블록 문자열, 활성 세션 판정 (§21.2)
- 실행 엔진(`plan-execute.sh`·`plan-rollback.sh`)의 `create_link {kind, method}`, junction 안전 판정, 삭제 규칙(끝 `/` 거부, 링크 먼저 unlink, 아카이브 복원 후 링크 재생성) (§21.8)
- `shell-rc.sh`의 PowerShell 프로필 편집: 인코딩·BOM·CRLF 보존, 시작·끝 마커 파서, 프로필 생성, UTF-16 수동 (§21.3, §21.8)
- 환경 확인 단계를 메뉴와 6개 sub-skill 첫 단계에 추가, 환경 파일에 감지 스냅샷/사용자 선택/계정별 블록 파일 분리 저장 (§21.1, D5)
- 외부 계정 인식(PowerShell 함수), 경로 키 정규화, `~/.claude` 직결 표시, 환경변수 미복원 경고 (§21.4)
- 조회의 마켓플레이스 주소 대조와 수동 수정 안내 (§21.5)
- Windows 활성 세션 게이트(lockfile·daemon 마커 차단, claude.exe 수 경고) (§21.8)
- 개발자 모드 꺼짐에서 `CLAUDE.md` 공유 생략·선택지 제외·"공유 안 됨" 표시 (D4)
- add의 프리셋 제거·항목 직접 선택 (D6, §7)
- README·매니페스트 플랫폼 표기 "macOS + Windows", 버전 0.5.0 (D7)
- `tests/preconditions.md` 검증 4, `tests/manual.md` MV-W1~MV-W9

**Excluded** *(이번 작업이 하지 않는 것)*

- Linux와 macOS bash·fish의 자동 셸 통합 (D7: 지금처럼 수동 안내)
- `settings.json` 자동 편집(마켓플레이스 주소 자동 수정은 v0.6 후보, §21.5)
- 외부(수동) 계정의 자동 수정·해제 (§13, §21.4: 수동 안내만)
- 파일 하드링크·복사로 `CLAUDE.md` 공유 (D4)
- keychain/Credential Manager 매핑, `.credentials.json` 처리 (§11, F11 기록만)
- 미반영 Codex 리뷰 P1-2(macOS 게이트 정밀화)·P1-4(`claude auth` feature-detect)·P2
- 기존 `quarantine` op의 없는 경로 처리(`plan-execute.sh:115-121`, 기존 동작)

## Existing Gate Survey

| Looked for | Found? | Usable? |
|---|---|---|
| architecture / boundary tests | 없음. 저장소에 아키텍처·경계 검사 파일 없음 | 해당 없음 |
| lint rules | 없음. shellcheck 설정·Python lint 설정 없음 (`find` 결과 파일 목록 = 매니페스트 2, commands 7, SKILL 7, scripts 9, tests 12, 문서 6) | 해당 없음 |
| custom build tasks (gradle, npm, make, ...) | `skills/account-partition/tests/unit/run.sh` — `*_test.sh`를 모두 실행하고 하나라도 실패하면 exit 1. 하네스 `tests/unit/assert.sh`(`assert_eq`/`assert_contains`/`assert_file_exists`/`assert_symlink_target`, `print_summary`가 실패 시 return 1) | **사용**. 새 테스트는 `*_test.sh` 이름으로 두면 `run.sh`가 자동 수집. 각 파일은 단독 실행 가능(exit code = 그 파일의 판정) |
| CI jobs | 없음. `.github/`·`.gitlab-ci.yml` 없음. git 훅 없음 | 해당 없음 — 모든 판정은 로컬 실행 |

기준선(2026-10-07, ca598df, 이 PC): `run.sh` 132 assert 중 75 통과 / 57 실패, exit 1. 파일별: discover 8/8, plan_build 25/25, shell_rc 14/14, matrix 0/11, plan_render 0/17, plan_shell_out 0/19, plan_execute 7/15, plan_rollback 6/7, safety 15/16. 원인은 plan-v0.5.md "기준선과 근본 원인" 표.

## Acceptance Criteria

명령은 저장소 루트에서 실행한다.

| # | Criterion (observable) | Basis | Source | Tier | Means | Command | Pass condition |
|---|---|---|---|---|---|---|---|
| AC1 | 이 Windows PC(Git Bash, 개발자 모드 꺼짐)에서 전체 단위 테스트를 실행하면, 기준선에서 실패하던 6개 파일을 포함해 모든 테스트 파일이 통과한다 | "57 failing tests pass on Windows", §21.7 | `request` | T1 | `existing` `skills/account-partition/tests/unit/run.sh` | `bash skills/account-partition/tests/unit/run.sh` | exit 0, 마지막 줄 `All test files passed.` |
| AC2 | OS 판정·override·경로 변환·계정 키·Python 출력 인코딩·bash 경로 해석이 `platform_test.sh`의 단정(`[P-01]`~`[P-13]`, `[K-01]`)대로 나온다 (모든 host) | §21.2 `ap_os`, §21.8 경로 표현 계약 | `upstream` | T1 | `new-test` `tests/unit/platform_test.sh::[P-01..P-13],[K-01]` | `bash skills/account-partition/tests/unit/platform_test.sh` | exit 0 |
| AC3 | Windows 호스트에서 공백·한글 경로의 junction 생성·판정·제거, 끝 `/` 거부, 복사본 검출, PowerShell UTF-8 출력, 실제 환경 감지가 `platform_windows_test.sh`(`[W-01]`~`[W-15]`)대로 나온다 | D3, §21.8 경로·링크 판정, §21.1 감지 | `upstream` | T1 | `new-test` `tests/unit/platform_windows_test.sh::[W-01..W-15]` | `bash skills/account-partition/tests/unit/platform_windows_test.sh` | Windows 호스트에서 exit 0, 출력에 `SKIP: windows host only` 없음 |
| AC4 | 실행 엔진에서 junction을 공유 해제해도 대상 내용이 그대로이고, 사본 복사가 중첩되지 않고, 링크가 복사본으로 생기면 그 단계가 실패해 롤백되며, 롤백이 junction을 되살린다 (`[E-01]`~`[E-11]`) | §21.2 사후 검사, §21.8 링크 판정 3가지 사고, §21.7 실패 주입 | `upstream` | T1 | `new-test` `tests/unit/link_engine_test.sh::[E-01..E-11]` | `bash skills/account-partition/tests/unit/link_engine_test.sh` | exit 0 |
| AC5 | 링크가 든 계정 디렉토리를 지우거나 아카이브해도 공유 보관소 내용이 그대로이고, 끝 `/` 경로는 거부되며, 아카이브 롤백 후 공유 링크가 다시 생긴다 (`[D-01]`~`[D-06]`) | §21.8 삭제 규칙 | `upstream` | T1 | `new-test` `tests/unit/engine_delete_test.sh::[D-01..D-06]` | `bash skills/account-partition/tests/unit/engine_delete_test.sh` | exit 0 |
| AC6 | 실행 엔진 소스에 `rm -rf`, `os.symlink(`, 이름만으로 실행하는 `bash`·`tar`가 없고, `platform.sh` 밖 실행 코드에 `ln -s`가 없다 (`[R-01]`~`[R-03]`) | §21.2 "Windows에서 `ln -s`를 직접 부르는 코드를 두지 않는다", §21.8 "링크일 수 있는 경로는 `rm -rf`로 지우지 않는다" | `upstream` | T1 | `new-test` `tests/unit/engine_rules_test.sh::[R-01..R-03]` | `bash skills/account-partition/tests/unit/engine_rules_test.sh` | exit 0 |
| AC7 | 환경 파일이 감지 스냅샷·사용자 선택·계정별 블록 파일을 따로 저장하고, 재호출은 스냅샷만 비교해 바뀐 키만 보고하며, 확인 화면 문구가 spec 예시와 같다 (`[V-01]`~`[V-13]`) | §21.1 1~3 | `upstream` | T1 | `new-test` `tests/unit/env_test.sh::[V-01..V-13]` | `bash skills/account-partition/tests/unit/env_test.sh` | exit 0 |
| AC8 | PowerShell 프로필에 블록을 넣고 빼도 BOM·CRLF·기존 바이트(한글 주석, 수동 함수)가 그대로이고, 없는 프로필은 UTF-8(BOM 없음)·CRLF로 만들어지며, UTF-16 프로필과 끝 마커 없는 블록은 손대지 않는다 (`[H-01]`~`[H-13]`) | §21.3 마커 블록, §21.8 프로필 인코딩 | `upstream` | T1 | `new-test` `tests/unit/shell_rc_ps_test.sh::[H-01..H-13]` | `bash skills/account-partition/tests/unit/shell_rc_ps_test.sh` | exit 0 |
| AC9 | plan 빌더가 macOS override에서 v0.4.4와 같은 구조(op 이름 `create_link`와 `kind`/`method`/`format` 필드만 추가)를, Windows에서 junction·PowerShell 블록·`CLAUDE.md` 생략(개발자 모드 꺼짐)을 만들고, 렌더·드라이런이 그에 맞는 문구·명령을 낸다 (`[B-01]`~`[B-08]`) | §21.2 `create_link`, §21.3, D4, D7 | `upstream` | T1 | `new-test` `tests/unit/plan_build_os_test.sh::[B-01..B-08]` | `bash skills/account-partition/tests/unit/plan_build_os_test.sh` | exit 0 |
| AC10 | PowerShell 프로필의 `claude-work`·`claude-dami` 형식 함수가 외부 계정으로 한 행씩 잡히고(경로 형식이 달라도), `~/.claude` 직결·환경변수 미복원·부분 등록·"공유 안 됨"이 조회에 표시되며, 조회 전후 프로필과 링크가 그대로다 (`[X-01]`~`[X-08]`) | §21.4, D4 표시, §13 부분 등록 | `upstream` | T1 | `new-test` `tests/unit/discover_ext_test.sh::[X-01..X-08]` | `bash skills/account-partition/tests/unit/discover_ext_test.sh` | exit 0 |
| AC11 | 공유 `known_marketplaces.json`과 계정 `extraKnownMarketplaces` 주소가 다르면 조회에 spec 문구의 경고와 수정 안내가 나오고, 같거나 한쪽에만 있으면 아무것도 나오지 않으며, `settings.json`의 다른 값은 출력되지 않는다 (`[M-01]`~`[M-06]`) | §21.5 | `upstream` | T1 | `new-test` `tests/unit/marketplace_test.sh::[M-01..M-06]` | `bash skills/account-partition/tests/unit/marketplace_test.sh` | exit 0 |
| AC12 | Windows에서 `daemon.lock`의 `pid`(또는 `supervisorPid`)가 살아 있거나 다른 account-partition lockfile이 살아 있으면 변경이 차단되고, 아니면 claude.exe 수가 경고로만 나온다. 기존 safety assert는 그대로 통과한다 (`[S-01]`~`[S-05]`) | §21.8 활성 세션 게이트 | `upstream` | T1 | `existing`+`new-test` `tests/unit/safety_test.sh::[S-01..S-05]` | `bash skills/account-partition/tests/unit/safety_test.sh` | exit 0 |
| AC13 | 메뉴와 6개 sub-skill이 환경 확인을 첫 단계로 두고, `~/.zshrc`를 하드코딩하지 않으며, add가 프리셋 없이 §7 문구로 항목을 고르고, README·매니페스트가 "macOS + Windows"와 0.5.0을 표기한다 (`[C-01]`~`[C-09]`) | §21.1, §21.6 SKILL, D6, D7 | `upstream` | T1 | `new-test` `tests/unit/docs_contract_test.sh::[C-01..C-09]` | `bash skills/account-partition/tests/unit/docs_contract_test.sh` | exit 0 |
| AC14 | macOS 호스트에서 전체 단위 테스트가 통과한다 | §21.7 "macOS 단위 테스트 유지", D7 | `upstream` | T2 | `existing` `skills/account-partition/tests/unit/run.sh` | `bash skills/account-partition/tests/unit/run.sh` (macOS에서) | exit 0, 마지막 줄 `All test files passed.` |
| AC15 | 사용자 Windows에서 add(`test1`) → 새 PowerShell 창의 `claude-test1` 실행·종료 후 같은 창 `$env:CLAUDE_CONFIG_DIR`이 비어 있음 → unlink까지 진행하면 junction·블록·아카이브가 MV-W2·MV-W5 기대 결과와 같고 공유 보관소가 그대로다 | D1, §21.3 환경변수 복원, §21.7 Windows MV | `upstream` | T4 | `tests/manual.md` MV-W2, MV-W5 | — | 사용자 확인(앵커는 이 파일 밖) |
| AC16 | 전 과정 후 기존 `claude-work`·`claude-dami`가 조회에 외부로 표시되고, 두 함수 줄·두 계정의 junction 대상·`settings.json` 수정 시각이 작업 전과 같다 | §21.7 "기존 `claude-work`, `claude-dami` 수동 셋업이 외부 계정으로 잡히고 건드려지지 않는지" | `upstream` | T4 | `tests/manual.md` MV-W3, MV-W9 | — | 사용자 확인 |
| AC17 | 첫 실행에 환경 확인 질문이 감지 결과대로 나오고, 두 번째 실행은 묻지 않으며, 개발자 모드를 켠 뒤에는 바뀐 항목만 다시 묻고 add에 글로벌 인스트럭션이 나타난다 | D5, D4, §21.1 | `upstream` | T4 | `tests/manual.md` MV-W1, MV-W6 | — | 사용자 확인 |

**`Source`** — `request` (partner's words) / `upstream` (ID in a frozen parent document) /
`review` (derived from a review) / `inferred` (no basis). Weigh `review` and `inferred` equally at Gate 1.

**Criteria count**: 17

**Why not split**: v0.5는 사용자가 `/plugin update` 한 번으로 받는 단일 버전이고, 엔진(AC2~AC12)만 끝나고 SKILL(AC13)이 없으면 Windows에서 어떤 흐름도 끝까지 쓸 수 없다(반대도 같다). 기준을 엔진 DoD와 SKILL DoD로 나누면 각 DoD가 혼자서는 검증 가능한 사용자 결과를 갖지 못한다. 대신 기준은 서브시스템마다 하나의 테스트 파일로 1:1 대응시켜 개별 판정이 되게 했다.

**Tier downgrade reasons** *(non-T1 rows only; approved with your human partner at Gate 1)*

- AC14 → T2: 이 작업 환경에는 macOS 호스트가 없다. 명령과 기대 출력은 고정돼 있고 사람이 macOS에서 다시 실행한다. Windows 호스트에서는 AC9·AC2의 `AP_OS_OVERRIDE=macos` 단정과 R3~R6이 macOS 출력을 대신 지킨다.
- AC15~AC17 → T4: 실제 PowerShell 창에서 함수가 로드되고 `claude`가 뜨는지, `AskUserQuestion` 화면이 어떻게 보이는지는 사람만 볼 수 있다(§14 "수동 검증 시나리오", D1 "검증 환경은 사용자 본인 Windows").

## Checker Artifacts

| Script | Path | Passing sample (must pass) | Violating sample (must catch) | Proof |
|---|---|---|---|---|
| 기존 assert 불변 검사 | `skills/account-partition/tests/unit/check_assertions_unchanged.sh` | 수정 전 트리: `bash skills/account-partition/tests/unit/check_assertions_unchanged.sh ca598df` → exit 0 | `tests/unit`을 임시 디렉토리에 복사하고 `plan_build_test.sh`의 `assert_contains "$plan" "side" "alias 이름"`을 `"side2"`로 바꾼 뒤 `--tree <임시>/unit` → exit 1, 빠진 줄 출력 | Task 1에서 두 실행 결과를 Evidence Log에 붙인다 |

## Regression Guards

Existing behavior this change could break. Exempt from RED.

| # | Behavior to keep | Command |
|---|---|---|
| R1 | 계정 디렉토리 발견(공유 보관소·백업 제외, default 포함) 8건 | `bash skills/account-partition/tests/unit/discover_test.sh` |
| R2 | zsh `~/.zshrc` 블록 추가·멱등·외부 alias 보존 14건 (zsh 편집 규칙 불변) | `bash skills/account-partition/tests/unit/shell_rc_test.sh` |
| R3 | macOS plan 빌더 출력 25건 (Task 6부터 파일 안에서 `AP_OS_OVERRIDE=macos` 고정) | `bash skills/account-partition/tests/unit/plan_build_test.sh` |
| R4 | 구 `create_symlink` plan의 렌더 출력 17건 (macOS 문구 불변) | `bash skills/account-partition/tests/unit/plan_render_test.sh` |
| R5 | 구 `create_symlink` plan의 드라이런 출력 19건 (macOS 명령 불변) | `bash skills/account-partition/tests/unit/plan_shell_out_test.sh` |
| R6 | 기준선의 통과 assert 75건을 포함해 기존 9개 테스트 파일의 assert 줄이 문자 그대로 남아 있다 (게이트로 감싸도 줄은 남는다) | `bash skills/account-partition/tests/unit/check_assertions_unchanged.sh ca598df` |

## Evidence Log

> Append only during implementation. Never delete or rewrite.

### AC1

```
[RED] 2026-10-07 ca598df (기준선, 이 PC: Windows 11 26200, Git Bash MINGW64, python3 3.12.5 win32, 개발자 모드 꺼짐)
$ bash skills/account-partition/tests/unit/run.sh
=== discover_test.sh ===        Tests: 8  Pass: 8  Fail: 0
=== matrix_test.sh ===          Tests: 11  Pass: 0  Fail: 11
=== plan_build_test.sh ===      Tests: 25  Pass: 25  Fail: 0
=== plan_execute_test.sh ===    Tests: 15  Pass: 7  Fail: 8
=== plan_render_test.sh ===     Tests: 17  Pass: 0  Fail: 17
=== plan_rollback_test.sh ===   Tests: 7  Pass: 6  Fail: 1
=== plan_shell_out_test.sh ===  Tests: 19  Pass: 0  Fail: 19
=== safety_test.sh ===          Tests: 16  Pass: 15  Fail: 1
=== shell_rc_test.sh ===        Tests: 14  Pass: 14  Fail: 0
exit=1
기대한 이유로 실패: UnicodeEncodeError 'cp949' (render·shell-out), WSL bash execvpe (matrix·rollback),
"symlink source does not exist: /tmp/..." / "archive_dir source missing: /tmp/..." (execute),
"백업 파일 권한 0600 expected: 600" (safety)
```

### R1–R3 (baseline)

```
[BASELINE] 2026-10-07 ca598df
discover_test.sh 8/8, shell_rc_test.sh 14/14, plan_build_test.sh 25/25 (각 exit 0)
주: plan_build_test.sh의 경로 assert는 기준선에서 MSYS 환경변수 변환 결과의 부분 문자열로 통과한다(plan-v0.5.md 기준선 표).
```

## Human Checks (T4)

> Only a human judges these. The agent does not fill this table.
> Anchors live outside this file — PR comment URL, commit SHA, issue link.

| # | What to confirm | Confirmed by | Date | Anchor |
|---|---|---|---|---|
| AC14 | macOS에서 `bash skills/account-partition/tests/unit/run.sh` → `All test files passed.` (T2 재실행) | | | |
| AC15 | MV-W2, MV-W5 기대 결과 | | | |
| AC16 | MV-W3, MV-W9 기대 결과 | | | |
| AC17 | MV-W1, MV-W6 기대 결과 | | | |

## Change Requests

> Only after freezing. Implementation stops until your human partner approves.
> Commit each amendment alone, before the rework commit.

| Target | Before | After | Reason | Approval |
|---|---|---|---|---|

## Final Verdict

> Every number is counted from the criteria table. A verdict whose SHA differs from the branch head is expired.

```
DoD VERDICT: v0.5-windows-design @ <commit SHA>
  criteria table:   17  (T1 13 · T2 1 · T3 0 · T4 3)
  T1/T2 automatic:  <p> of 14 PASS
  T3 recorded:      0 of 0
  T4 human:         <r> of 3 confirmed, <3-r> pending
  change requests:  0
  =>
```

**Items awaiting a human**

- Gate 1 결정: plan-v0.5.md의 DECISION-1(Windows 백업 0600), DECISION-2(선택지 5개와 `AskUserQuestion` 4개 제한)
- AC14(macOS 재실행), AC15~AC17(Windows 수동 시나리오)
