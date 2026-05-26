# account-partition v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude CLI를 여러 OAuth 계정용으로 분리·관리하는 슬래시 명령(`/account-partition`)을 별도 plugin marketplace repo로 만들어 GitHub에 공개한다. v1은 계정 추가·조회·공유 항목 수정만.

**Architecture:**
- 슬래시 명령(`commands/account-partition.md`) → SKILL.md(`skills/account-partition/SKILL.md`)이 LLM에게 흐름을 지시
- 디스크 조작은 bash 헬퍼(`skills/account-partition/scripts/*.sh`)로 분리 — SKILL.md가 헬퍼를 호출
- 모든 파괴적 변경은 단일 operation plan 객체(JSON)로 구성·렌더·실행·롤백
- TDD가 적절한 부분(헬퍼 스크립트)은 bash assert 기반 단위 테스트, 나머지(SKILL.md·통합)는 수동 검증 시나리오

**Tech Stack:** bash 5+, jq, macOS `security`(keychain) 명령, zsh 5+, Python 3 (JSON·해시 보조)

**Spec:** `skills/account-partition/design.md` (리비전 3)

---

## TDD Applicability

이 plan에는 두 종류 task가 섞여 있음:

- **TDD 가능 (단위 테스트)**: bash 헬퍼 스크립트(`discover.sh`, `matrix.sh`, `plan-render.sh` 등) — 입력 모의 환경 → 출력 검증
- **TDD 비적용 (수동 검증)**: SKILL.md·commands/*.md·references/*.md — 자연어 인스트럭션 또는 문서. 작성 후 `tests/manual.md` 시나리오로 수동 검증

각 task에 "[TDD]" 또는 "[Manual]" 태그를 붙여 구분.

작업 디렉토리: `~/workspace/gang/account-partition/` (별도 plugin repo)
브랜치: `main` (별도 본인 repo이므로 main 직접 commit + push)
Repo: `glaude-skills/account-partition` (또는 fallback `GGGGGANG/account-partition`)

---

## File Structure (구현 후 결과물)

새 plugin repo 루트 기준:

```
.claude-plugin/
  marketplace.json                    marketplace 메타데이터
  plugin.json                         plugin 메타데이터

commands/
  account-partition.md                슬래시 명령 정의

skills/account-partition/
  SKILL.md                            메인 흐름 인스트럭션 (한국어)
  design.md                           (이미 작성됨)
  plan.md                             (이 문서)
  references/
    item-mapping.md                   항목 ↔ 라벨 매핑 상세
    shell-integration.md              셸별 통합 디테일
  scripts/
    discover.sh                       외부 alias·계정 발견
    keychain-discover.sh              keychain entry 매칭
    matrix.sh                         공유/격리 매트릭스 렌더
    safety.sh                         활성 세션 감지·lockfile·백업
    shell-rc.sh                       zshrc 자동 편집
    plan-build.sh                     액션별 operation plan 빌더
    plan-render.sh                    plan → 사람이 읽을 텍스트
    plan-execute.sh                   plan 실행 엔진
    plan-shell-out.sh                 plan → 셸 명령 시퀀스(드라이런)
    plan-rollback.sh                  롤백 처리
  tests/
    preconditions.md                  슬래시 명령·keychain hash 검증 결과
    manual.md                         수동 검증 시나리오
    unit/
      run.sh                          모든 단위 테스트 실행
      assert.sh                       공통 assertion 함수
      discover_test.sh                discover.sh 단위 테스트
      matrix_test.sh                  matrix.sh 단위 테스트
      plan_render_test.sh             plan-render.sh 단위 테스트
      plan_shell_out_test.sh          plan-shell-out.sh 단위 테스트
      shell_rc_test.sh                shell-rc.sh 단위 테스트

README.md                             repo 소개 + 사용자 설치 절차
LICENSE                               MIT
.gitignore
```

---

## Phase A — Repo 골격 + 사전 검증

새 plugin repo 골격(marketplace.json, plugin.json, README 등)을 만들고 GitHub에 push해 사용자가 install할 수 있게 한다. 그 후 슬래시 명령 발견 + keychain hash 알고리즘 검증.

### Task A.1: Plugin repo 골격 + 슬래시 명령 발견 검증 [Manual]

**Files:**
- Create: `.claude-plugin/marketplace.json`
- Create: `.claude-plugin/plugin.json`
- Create: `commands/account-partition.md`
- Create: `skills/account-partition/SKILL.md` (최소 frontmatter + placeholder)
- Create: `skills/account-partition/tests/preconditions.md`
- Create: `README.md`, `LICENSE`, `.gitignore`

- [ ] **Step 1: `.claude-plugin/marketplace.json`**

```json
{
  "name": "account-partition",
  "description": "Plugin for managing multiple Claude CLI OAuth accounts via aliases (macOS+zsh)",
  "owner": {"name": "gang00"},
  "plugins": [
    {
      "name": "account-partition",
      "description": "Manage multiple Claude CLI OAuth accounts via CLAUDE_CONFIG_DIR aliases. v1: add, list, modify shared items.",
      "version": "0.1.0",
      "source": "./",
      "author": {"name": "gang00"}
    }
  ]
}
```

- [ ] **Step 2: `.claude-plugin/plugin.json`**

```json
{
  "name": "account-partition",
  "description": "Manage multiple Claude CLI OAuth accounts via CLAUDE_CONFIG_DIR aliases. v1: add, list, modify shared items.",
  "version": "0.1.0",
  "author": {"name": "gang00"},
  "homepage": "https://github.com/<org>/account-partition",
  "repository": "https://github.com/<org>/account-partition",
  "license": "MIT",
  "keywords": ["claude", "cli", "accounts", "aliases", "macos"]
}
```

(`<org>`은 실제 결정된 org 또는 `GGGGGANG`로 채움)

- [ ] **Step 3: 최소 SKILL.md 작성**

```markdown
---
name: account-partition
description: "Claude CLI를 여러 OAuth 계정용으로 분리·관리하는 스킬. v1은 추가·조회·공유 항목 수정."
---

# account-partition (v1)

이 스킬은 검증 단계입니다. 메인 흐름은 다음 phase에서 작성됩니다.

호출되었다면 다음 메시지를 출력하세요:
"account-partition 스킬이 정상적으로 호출되었습니다. (검증용 placeholder)"
```

- [ ] **Step 4: commands/account-partition.md 작성**

```markdown
---
description: "Claude CLI를 여러 OAuth 계정용으로 분리·관리 (추가·조회·공유 항목 수정)"
---

account-partition 스킬을 실행해.
```

- [ ] **Step 5: tests/preconditions.md 양식**

```markdown
# 구현 전 검증 결과

## 검증 1: 슬래시 명령 발견 경로

검증일: <YYYY-MM-DD>
검증자: <human>

### 사전 조건

- repo가 GitHub에 push되어 있고 `<org>/account-partition` marketplace로 add됨
- `/plugin install account-partition@account-partition` 실행 완료
- plugin cache 위치(`~/.claude*/plugins/cache/account-partition/account-partition/0.1.0/`)에 commands·skills 디렉토리 노출 확인

### 검증 절차

새 Claude Code 세션에서:
1. `/` 입력 후 자동완성 목록에 `account-partition` (또는 `account-partition:account-partition`) 표시 확인
2. `/account-partition` 실행 → SKILL.md placeholder 메시지 출력 확인

### 결과

**통과 조건**: 자동완성에 노출 + 호출 시 placeholder 메시지 정상 출력

- `/account-partition` 노출: [TBD — 노출됨 / 노출 안 됨]
- `/account-partition:account-partition` 노출: [TBD]
- SKILL.md placeholder 메시지 출력: [TBD — 정상 / 다른 메시지 / 실행 안 됨]
- plugin cache 경로 확인: [TBD]

### 메모

[발견된 이슈·캐시 갱신 절차·다른 호출 경로 등 기록]

---

## 검증 2: Keychain service 이름 hash 규칙

(Task A.2에서 채울 예정 — 양식만 생성)

검증일: <YYYY-MM-DD>

### 알고리즘
- 해시 함수: [TBD — SHA-256 / MD5 / CRC32 / 기타]
- 입력 정규화: [TBD]
- 출력 절단: [TBD]

### 검증 매트릭스

이 검증은 머신·사용자마다 실제 값이 다릅니다. 검증자가 본인 환경의 keychain entry suffix를 캡처해 채워 넣으세요.

| CONFIG_DIR | 실제 suffix | 계산 결과 | 일치 |
|---|---|---|---|
| `~/.claude` | [본인 환경 값] | [본인 환경 값] | [TBD] |
| `~/.claude-<예시>` | [본인 환경 값] | [본인 환경 값] | [TBD] |

`security dump-keychain 2>/dev/null | grep "Claude Code-credentials"` 출력으로 실제 suffix 확인 가능.

### 메모
```

- [ ] **Step 6: README.md / LICENSE / .gitignore**

`README.md`:
```markdown
# account-partition

Manage multiple Claude CLI OAuth accounts via `CLAUDE_CONFIG_DIR` aliases (e.g., `claude-work`, `claude-personal`) with user-selectable shared/isolated items between accounts.

**Status:** v1 — Add, List, modify shared items (Unlink and external alias auto-modification in v2)
**Platforms:** macOS + zsh

## Install

```
/plugin marketplace add <org>/account-partition
/plugin install account-partition@account-partition
```

## Usage

```
/account-partition
```

Choose an action: 계정 추가 연동 / 계정 조회 / 계정의 공유 항목 수정 / 계정 연동 해제 (v1 미지원).

## Design

See `skills/account-partition/design.md` and `skills/account-partition/plan.md`.

## License

MIT
```

`LICENSE`: 표준 MIT 텍스트, copyright = `2026 gang00`.

`.gitignore`:
```
.DS_Store
*.bak.*
.account-partition-state.json
```

- [ ] **Step 7: git init + 첫 commit**

```bash
cd ~/workspace/gang/account-partition
git init
git add .claude-plugin commands skills README.md LICENSE .gitignore
git commit -m "feat: account-partition v0.1.0 plugin 골격 + 검증 양식"
```

- [ ] **Step 8: GitHub repo 생성 + push (사용자 명시 승인 필요)**

```bash
gh repo create <org>/account-partition --public \
  --description "Manage multiple Claude CLI OAuth accounts via CLI aliases" \
  --source=. --remote=origin

git branch -M main
git push -u origin main
```

- [ ] **Step 9: 사용자가 marketplace add + install (인터랙티브)**

새 Claude Code 세션에서:
```
/plugin marketplace add <org>/account-partition
/plugin install account-partition@account-partition
```

- [ ] **Step 10: 슬래시 명령 발견 검증 (사용자)**

1. `/account-partition` 자동완성에 뜨는지
2. 호출 시 placeholder 메시지 출력되는지
3. 결과를 `tests/preconditions.md` 검증 1 섹션에 채움

검증 실패 시 plan 중단, 사용자에게 보고.

- [ ] **Step 11: preconditions.md 결과 commit + push**

```bash
git add skills/account-partition/tests/preconditions.md
git commit -m "test: 검증 1 (슬래시 명령 발견) 결과 기록"
git push
```

---

### Task A.2: Keychain service 이름 hash 규칙 reverse engineer [Manual]

**Files:**
- Modify: `skills/account-partition/tests/preconditions.md` (검증 결과 추가)

- [ ] **Step 1: 기존 keychain entry 수집**

```bash
security dump-keychain 2>/dev/null | grep "Claude Code-credentials" | sort -u
```

현재 시스템에 알려진 매핑(사용자 환경):
- `~/.claude` → `Claude Code-credentials` (suffix 없음 = default)
- `~/.claude-work` → `Claude Code-credentials-64ad4bd9`
- `~/.claude-personal` → `Claude Code-credentials-c28821e0`

- [ ] **Step 2: hash 후보 알고리즘 시도**

각 CONFIG_DIR 경로에 대해 다음 후보를 계산해 suffix와 일치 여부 확인:

```bash
# 후보 1: SHA-256 절단 (8자, 16자)
python3 -c "import hashlib; print(hashlib.sha256(b'/Users/gang/.claude-work').hexdigest()[:8])"
python3 -c "import hashlib; print(hashlib.sha256(b'/Users/gang/.claude-work').hexdigest()[:16])"

# 후보 2: MD5 절단
python3 -c "import hashlib; print(hashlib.md5(b'/Users/gang/.claude-work').hexdigest()[:8])"

# 후보 3: CRC32
python3 -c "import zlib; print(format(zlib.crc32(b'/Users/gang/.claude-work') & 0xffffffff, '08x'))"

# 후보 4: 다른 정규화 (홈 디렉토리 ~, trailing slash)
for path in '/Users/gang/.claude-work' '~/.claude-work' '/Users/gang/.claude-work/' '$HOME/.claude-work'; do
  python3 -c "import hashlib,sys; print('${path}:', hashlib.sha256('${path}'.encode()).hexdigest()[:8])"
done
```

기대: 후보 중 하나가 `64ad4bd9` 또는 `c28821e0`과 일치.

- [ ] **Step 3: 알고리즘 검증 — 새 entry 생성으로 확인**

검증된 알고리즘이 실제 CC가 사용하는 것인지 confirm하려면:
1. 새 임시 CONFIG_DIR 만들기: `mkdir /tmp/claude-test-$$`
2. `CLAUDE_CONFIG_DIR=/tmp/claude-test-$$ claude` 실행 후 `/login` 시도
3. 생성된 keychain entry suffix 확인
4. step 2의 후보 알고리즘으로 같은 suffix가 산출되는지 비교

- [ ] **Step 4: 결과를 preconditions.md에 기록**

```markdown
## 검증 2: Keychain service 이름 hash 규칙

검증일: <YYYY-MM-DD>

### 알고리즘
- 해시 함수: <SHA-256 / MD5 / CRC32 / 기타>
- 입력 정규화: <절대경로 / ~ 확장 / trailing slash 처리 등>
- 출력 절단: <suffix 길이>

### 검증 매트릭스

| CONFIG_DIR | 실제 suffix | 계산 결과 | 일치 |
|---|---|---|---|
| `/Users/gang/.claude-work` | `64ad4bd9` | <계산값> | <O/X> |
| `/Users/gang/.claude-personal` | `c28821e0` | <계산값> | <O/X> |
| `/tmp/claude-test-NNNN` | <캡처값> | <계산값> | <O/X> |

### 메모

<버전·OS·CC 빌드 정보, 알 수 없는 변동 요소>
```

- [ ] **Step 5: 검증 실패 시 처리**

알고리즘 reverse engineer 실패하면 v1에서 keychain 매칭은 "⚠ 추정"으로만 표시하는 fallback 적용. design.md §11에 이미 명시됨.

- [ ] **Step 6: Commit**

```bash
git add skills/account-partition/tests/preconditions.md
git commit -m "test(account-partition): keychain service 이름 hash 규칙 검증"
```

---

### Task A.3: 스킬 디렉토리 골격 완성 [Manual]

**Files:**
- Create: `skills/account-partition/scripts/` (디렉토리)
- Create: `skills/account-partition/references/` (디렉토리)
- Create: `skills/account-partition/tests/unit/` (디렉토리)
- Create: `skills/account-partition/tests/unit/assert.sh`
- Create: `skills/account-partition/tests/unit/run.sh`

- [ ] **Step 1: 디렉토리 생성**

```bash
cd ~/.claude-shared/plugins/marketplaces/superpowers-dev/skills/account-partition
mkdir -p scripts references tests/unit
```

- [ ] **Step 2: assert.sh — 공통 assertion 함수 작성**

```bash
cat > tests/unit/assert.sh <<'EOF'
#!/usr/bin/env bash
# 공통 assertion 함수. 각 *_test.sh에서 source.

# Color codes (TTY일 때만 색상)
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  NC=''
fi

# Global counters
ASSERT_PASS=0
ASSERT_FAIL=0
ASSERT_FAILURES=()

assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="${3:-}"

  if [[ "$actual" == "$expected" ]]; then
    ASSERT_PASS=$((ASSERT_PASS + 1))
    echo -e "  ${GREEN}✓${NC} ${msg:-assertion passed}"
  else
    ASSERT_FAIL=$((ASSERT_FAIL + 1))
    local detail="${msg:-assertion failed}\n    expected: $expected\n    actual:   $actual"
    ASSERT_FAILURES+=("$detail")
    echo -e "  ${RED}✗${NC} $detail"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-}"

  if [[ "$haystack" == *"$needle"* ]]; then
    ASSERT_PASS=$((ASSERT_PASS + 1))
    echo -e "  ${GREEN}✓${NC} ${msg:-contains '$needle'}"
  else
    ASSERT_FAIL=$((ASSERT_FAIL + 1))
    local detail="${msg:-does not contain '$needle'}\n    haystack: $haystack"
    ASSERT_FAILURES+=("$detail")
    echo -e "  ${RED}✗${NC} $detail"
  fi
}

assert_file_exists() {
  local path="$1"
  local msg="${2:-file exists: $path}"

  if [[ -e "$path" ]]; then
    ASSERT_PASS=$((ASSERT_PASS + 1))
    echo -e "  ${GREEN}✓${NC} $msg"
  else
    ASSERT_FAIL=$((ASSERT_FAIL + 1))
    ASSERT_FAILURES+=("$msg")
    echo -e "  ${RED}✗${NC} $msg"
  fi
}

assert_symlink_target() {
  local link="$1"
  local expected_target="$2"
  local msg="${3:-symlink $link -> $expected_target}"

  if [[ -L "$link" ]]; then
    local actual_target
    actual_target=$(readlink "$link")
    if [[ "$actual_target" == "$expected_target" ]]; then
      ASSERT_PASS=$((ASSERT_PASS + 1))
      echo -e "  ${GREEN}✓${NC} $msg"
      return
    fi
  fi
  ASSERT_FAIL=$((ASSERT_FAIL + 1))
  ASSERT_FAILURES+=("$msg")
  echo -e "  ${RED}✗${NC} $msg"
}

print_summary() {
  local total=$((ASSERT_PASS + ASSERT_FAIL))
  echo ""
  echo "  Tests: $total  Pass: $ASSERT_PASS  Fail: $ASSERT_FAIL"
  if [[ $ASSERT_FAIL -gt 0 ]]; then
    return 1
  fi
}

# Sandbox helpers
make_sandbox() {
  local sb
  sb=$(mktemp -d -t account-partition-test.XXXXXX)
  echo "$sb"
}

cleanup_sandbox() {
  local sb="$1"
  [[ -d "$sb" ]] && rm -rf "$sb"
}
EOF
chmod +x tests/unit/assert.sh
```

- [ ] **Step 3: run.sh — 테스트 러너 작성**

```bash
cat > tests/unit/run.sh <<'EOF'
#!/usr/bin/env bash
# 단위 테스트 전체 실행.
# 사용: bash tests/unit/run.sh
set -uo pipefail

cd "$(dirname "$0")"

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_FILES=()

for test_file in *_test.sh; do
  [[ -f "$test_file" ]] || continue
  echo "=== $test_file ==="
  if bash "$test_file"; then
    :
  else
    FAILED_FILES+=("$test_file")
  fi
done

echo ""
echo "=========================="
if [[ ${#FAILED_FILES[@]} -gt 0 ]]; then
  echo "FAILED test files:"
  for f in "${FAILED_FILES[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
echo "All test files passed."
EOF
chmod +x tests/unit/run.sh
```

- [ ] **Step 4: run.sh 실행해서 0개 테스트 통과 확인**

```bash
bash tests/unit/run.sh
```

Expected: "All test files passed." (테스트 파일 없으면 그냥 통과)

- [ ] **Step 5: Commit**

```bash
git add skills/account-partition/scripts skills/account-partition/references skills/account-partition/tests
git commit -m "feat(account-partition): 디렉토리 골격 + 테스트 인프라(assert.sh, run.sh)"
```

---

## Phase B — 발견 로직 (discover.sh, keychain-discover.sh)

외부에서 만든 alias·디렉토리·keychain entry를 발견하고 매칭한다. 이 phase는 List 액션의 기반.

### Task B.1: discover.sh — 디렉토리 스캔 [TDD]

**Files:**
- Create: `skills/account-partition/scripts/discover.sh`
- Create: `skills/account-partition/tests/unit/discover_test.sh`

- [ ] **Step 1: 실패 테스트 작성**

```bash
cat > tests/unit/discover_test.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

# 모의 환경: 임시 HOME 디렉토리
sb=$(make_sandbox)
trap 'cleanup_sandbox "$sb"' EXIT

# 시나리오 1: 일반 alias 디렉토리만
mkdir -p "$sb/.claude-work"
echo '{"oauthAccount":{"emailAddress":"test@example.com"}}' > "$sb/.claude-work/.claude.json"
mkdir -p "$sb/.claude-personal"
echo '{"oauthAccount":{"emailAddress":"other@example.com"}}' > "$sb/.claude-personal/.claude.json"

# 시나리오 2: 공유 보관소 (제외 대상)
mkdir -p "$sb/.claude-shared"

# 시나리오 3: 비-디렉토리 (제외)
touch "$sb/.claude.json"

# 시나리오 4: 백업 잔존물 (제외)
touch "$sb/.claude-side.removed.20260101.tar.gz"
mkdir -p "$sb/.claude-old"  # .claude.json 없음 = 후보 미충족

# default ~/.claude
mkdir -p "$sb/.claude"

# Run
out=$(HOME="$sb" SHARED_POOL="$sb/.claude-shared" bash "$SCRIPTS/discover.sh" list-dirs 2>&1)

echo "--- discover.sh list-dirs output ---"
echo "$out"
echo "---"

assert_contains "$out" ".claude-work" "발견: .claude-work"
assert_contains "$out" ".claude-personal" "발견: .claude-personal"
assert_contains "$out" ".claude" "발견: .claude (default)"

# 제외 검증
if [[ "$out" == *".claude-shared"* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL + 1)); ASSERT_FAILURES+=(".claude-shared 잘못 포함됨")
  echo "  ✗ .claude-shared 잘못 포함됨"
else
  ASSERT_PASS=$((ASSERT_PASS + 1)); echo "  ✓ .claude-shared 제외 OK"
fi

# 비-계정 후보 (.claude-old)는 "candidate-ignored" 카테고리로 분리되어야 함
out_ignored=$(HOME="$sb" SHARED_POOL="$sb/.claude-shared" bash "$SCRIPTS/discover.sh" list-ignored 2>&1)
assert_contains "$out_ignored" ".claude-old" ".claude-old는 무시된 후보로 표시"

print_summary
EOF
chmod +x tests/unit/discover_test.sh
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

```bash
bash tests/unit/run.sh
```

Expected: FAIL (`discover.sh` 미존재)

- [ ] **Step 3: discover.sh 작성**

```bash
cat > scripts/discover.sh <<'EOF'
#!/usr/bin/env bash
# 외부 alias·계정 발견.
# 사용:
#   discover.sh list-dirs          → 계정 후보 디렉토리 절대경로 한 줄씩 출력
#   discover.sh list-ignored       → 무시된 후보 디렉토리 한 줄씩 출력
#   discover.sh meta <dir>         → 단일 디렉토리의 메타데이터 (계정 이메일 등) JSON
#
# 환경변수:
#   HOME         (기본: $HOME)
#   SHARED_POOL  (기본: $HOME/.claude-shared)

set -uo pipefail

HOME="${HOME:?HOME is required}"
SHARED_POOL="${SHARED_POOL:-$HOME/.claude-shared}"

is_account_candidate() {
  local dir="$1"

  # .claude.json 존재하면 후보
  [[ -f "$dir/.claude.json" ]] && return 0

  # 추가 조건은 keychain·alias 매칭 — discover.sh에서는 .claude.json만 1차 판별
  # alias·keychain 매칭은 keychain-discover.sh + shell-rc.sh에서 별도로
  return 1
}

list_dirs() {
  local exclude_pool
  exclude_pool=$(cd "$(dirname "$SHARED_POOL")" 2>/dev/null && pwd)/$(basename "$SHARED_POOL")

  shopt -s nullglob dotglob 2>/dev/null
  for entry in "$HOME"/.claude "$HOME"/.claude-*; do
    [[ -d "$entry" ]] || continue

    # 공유 보관소 제외
    [[ "$entry" == "$SHARED_POOL" ]] && continue
    [[ "$entry" == "$exclude_pool" ]] && continue

    # 백업·격리 보존 제외
    [[ "$entry" == *.tar.gz ]] && continue
    [[ "$entry" == *.bak.* ]] && continue
    [[ "$entry" == *.removed.* ]] && continue
    [[ "$(basename "$entry")" == ".account-partition-quarantine" ]] && continue

    # 계정 후보 조건
    if is_account_candidate "$entry"; then
      echo "$entry"
    fi
  done
}

list_ignored() {
  shopt -s nullglob dotglob 2>/dev/null
  for entry in "$HOME"/.claude-*; do
    [[ -d "$entry" ]] || continue
    [[ "$entry" == "$SHARED_POOL" ]] && continue
    [[ "$entry" == *.bak.* ]] && continue
    [[ "$entry" == *.removed.* ]] && continue

    if ! is_account_candidate "$entry"; then
      echo "$entry"
    fi
  done
}

meta_for_dir() {
  local dir="$1"
  local email=""

  if [[ -f "$dir/.claude.json" ]]; then
    email=$(python3 -c "
import json, sys
try:
    d = json.load(open('$dir/.claude.json'))
    print(d.get('oauthAccount', {}).get('emailAddress', ''))
except Exception:
    pass
" 2>/dev/null)
  fi

  local name
  name=$(basename "$dir")
  if [[ "$name" == ".claude" ]]; then
    name="claude (기본)"
  else
    name="${name#.}"  # .claude-work → claude-work
  fi

  python3 -c "
import json
print(json.dumps({
  'dir': '$dir',
  'alias': '$name',
  'email': '$email',
}))
"
}

cmd="${1:-help}"
case "$cmd" in
  list-dirs)    list_dirs ;;
  list-ignored) list_ignored ;;
  meta)         meta_for_dir "$2" ;;
  *)
    echo "Usage: $0 {list-dirs|list-ignored|meta <dir>}" >&2
    exit 1
    ;;
esac
EOF
chmod +x scripts/discover.sh
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

```bash
bash tests/unit/run.sh
```

Expected: 모든 assertion PASS

- [ ] **Step 5: Commit**

```bash
git add skills/account-partition/scripts/discover.sh skills/account-partition/tests/unit/discover_test.sh
git commit -m "feat(account-partition): discover.sh + 단위 테스트 (디렉토리 스캔)"
```

---

### Task B.2: keychain-discover.sh — keychain entry 매칭 [TDD]

**Files:**
- Create: `skills/account-partition/scripts/keychain-discover.sh`
- Create: `skills/account-partition/tests/unit/keychain_discover_test.sh`

⚠ 이 task는 **Phase A.2의 hash 알고리즘 검증 결과**를 사용. 검증 실패였으면 본 task는 "추정" 모드로 작성 (warning만 출력).

- [ ] **Step 1: 실패 테스트 작성**

`tests/preconditions.md`에서 확인된 알고리즘이 SHA-256[:8]이라고 가정 (검증 결과에 따라 수정).

```bash
cat > tests/unit/keychain_discover_test.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

# 알고리즘 검증: 같은 경로 → 같은 hash
hash1=$(bash "$SCRIPTS/keychain-discover.sh" hash-for "/Users/gang/.claude-work")
hash2=$(bash "$SCRIPTS/keychain-discover.sh" hash-for "/Users/gang/.claude-work")
assert_eq "$hash1" "$hash2" "동일 경로 → 동일 hash"

# 다른 경로 → 다른 hash
hash3=$(bash "$SCRIPTS/keychain-discover.sh" hash-for "/Users/gang/.claude-personal")
[[ "$hash1" != "$hash3" ]] && {
  ASSERT_PASS=$((ASSERT_PASS + 1)); echo "  ✓ 다른 경로 → 다른 hash"
} || {
  ASSERT_FAIL=$((ASSERT_FAIL + 1)); echo "  ✗ 다른 경로인데 hash 충돌"
}

# 실제 검증된 값 (Phase A.2 결과로 채움)
# expected_work_hash="64ad4bd9"  # ← preconditions.md에서 확인된 값
# assert_eq "$hash1" "$expected_work_hash" "사용자 .claude-work hash 일치"

print_summary
EOF
chmod +x tests/unit/keychain_discover_test.sh
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

```bash
bash tests/unit/run.sh
```

Expected: FAIL (keychain-discover.sh 미존재)

- [ ] **Step 3: keychain-discover.sh 작성**

검증된 알고리즘으로 작성. SHA-256[:8] 가정 — Phase A.2 결과에 맞춰 조정.

```bash
cat > scripts/keychain-discover.sh <<'EOF'
#!/usr/bin/env bash
# Keychain entry 매칭.
# 사용:
#   keychain-discover.sh list-entries          → 모든 Claude Code-credentials entry suffix 한 줄씩
#   keychain-discover.sh hash-for <CONFIG_DIR> → 그 디렉토리에 대응하는 expected suffix
#   keychain-discover.sh match <CONFIG_DIR>    → 해당 entry 존재 여부 (exit 0/1) + verbose

set -uo pipefail

# Phase A.2 검증된 알고리즘. preconditions.md 참조.
# 알고리즘 확정 안 되었으면 ALGO=unknown 으로 설정하면 모든 매칭이 "추정"으로 표시됨.
ALGO="${KEYCHAIN_HASH_ALGO:-sha256-8}"   # 기본 가정

hash_for_path() {
  local path="$1"

  case "$ALGO" in
    sha256-8)
      python3 -c "import hashlib; print(hashlib.sha256(b'$path').hexdigest()[:8])"
      ;;
    sha256-16)
      python3 -c "import hashlib; print(hashlib.sha256(b'$path').hexdigest()[:16])"
      ;;
    md5-8)
      python3 -c "import hashlib; print(hashlib.md5(b'$path').hexdigest()[:8])"
      ;;
    crc32)
      python3 -c "import zlib; print(format(zlib.crc32(b'$path') & 0xffffffff, '08x'))"
      ;;
    unknown)
      echo "unknown"
      ;;
    *)
      echo "Error: unknown ALGO=$ALGO" >&2
      exit 1
      ;;
  esac
}

list_entries() {
  security dump-keychain 2>/dev/null \
    | grep '"svce"<blob>="Claude Code-credentials' \
    | sed -E 's/.*"Claude Code-credentials-?([^"]*)".*/\1/' \
    | sort -u
}

match() {
  local dir="$1"
  local expected
  expected=$(hash_for_path "$dir")

  if [[ "$ALGO" == "unknown" ]]; then
    echo "match: unknown (hash algorithm not verified)"
    return 2
  fi

  if list_entries | grep -qx "$expected"; then
    echo "match: $expected"
    return 0
  fi
  echo "no-match (expected: $expected)"
  return 1
}

cmd="${1:-help}"
case "$cmd" in
  list-entries) list_entries ;;
  hash-for)     hash_for_path "$2" ;;
  match)        match "$2" ;;
  *)
    echo "Usage: $0 {list-entries|hash-for <path>|match <path>}" >&2
    exit 1
    ;;
esac
EOF
chmod +x scripts/keychain-discover.sh
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

```bash
bash tests/unit/run.sh
```

Expected: PASS (hash 일관성 테스트 통과. 사용자 실제 값 일치는 Phase A.2 검증 후 별도 단계에서)

- [ ] **Step 5: Commit**

```bash
git add skills/account-partition/scripts/keychain-discover.sh skills/account-partition/tests/unit/keychain_discover_test.sh
git commit -m "feat(account-partition): keychain-discover.sh (hash 매칭)"
```

---

### Task B.3: shell-rc.sh — zshrc alias 발견·자동 편집 [TDD]

**Files:**
- Create: `skills/account-partition/scripts/shell-rc.sh`
- Create: `skills/account-partition/tests/unit/shell_rc_test.sh`

- [ ] **Step 1: 실패 테스트 작성**

```bash
cat > tests/unit/shell_rc_test.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

sb=$(make_sandbox)
trap 'cleanup_sandbox "$sb"' EXIT

# 시나리오 1: 빈 zshrc → alias 추가
rc="$sb/.zshrc"
touch "$rc"
bash "$SCRIPTS/shell-rc.sh" add "$rc" "work" "$sb/.claude-work"

# 검증: 주석 + alias 라인이 추가됨
content=$(cat "$rc")
assert_contains "$content" "# account-partition: work" "관리 주석 추가"
assert_contains "$content" 'alias claude-work=' "alias 라인 추가"
assert_contains "$content" 'CLAUDE_CONFIG_DIR' "CLAUDE_CONFIG_DIR 포함"
assert_contains "$content" "$sb/.claude-work" "CONFIG_DIR 경로 포함 (확장 후)"

# 시나리오 2: 같은 이름 다시 add → idempotent (블록 교체)
old_line_count=$(wc -l < "$rc")
bash "$SCRIPTS/shell-rc.sh" add "$rc" "work" "$sb/.claude-work-NEW"
new_line_count=$(wc -l < "$rc")
assert_eq "$old_line_count" "$new_line_count" "idempotent: 라인 수 동일"
assert_contains "$(cat "$rc")" "$sb/.claude-work-NEW" "교체된 경로 반영"

# 시나리오 3: list — 발견된 alias 출력
out=$(bash "$SCRIPTS/shell-rc.sh" list "$rc")
assert_contains "$out" "work" "list에 work 표시"

# 시나리오 4: 외부 alias (주석 없는 형태) 발견
echo 'alias claude-external="CLAUDE_CONFIG_DIR=/tmp/x command claude"' >> "$rc"
out2=$(bash "$SCRIPTS/shell-rc.sh" list "$rc")
assert_contains "$out2" "external" "주석 없는 외부 alias도 list에 표시"
assert_contains "$out2" "external:external" "외부는 source=external로 표시"

print_summary
EOF
chmod +x tests/unit/shell_rc_test.sh
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

```bash
bash tests/unit/run.sh
```

Expected: FAIL (shell-rc.sh 미존재)

- [ ] **Step 3: shell-rc.sh 작성**

```bash
cat > scripts/shell-rc.sh <<'EOF'
#!/usr/bin/env bash
# zshrc alias 라인 자동 편집·발견.
# 사용:
#   shell-rc.sh add <rc> <name> <config_dir>     → 주석 블록 + alias 추가/교체 (idempotent)
#   shell-rc.sh remove <rc> <name>               → 주석 블록 + alias 제거 (스킬 관리 블록만)
#   shell-rc.sh list <rc>                        → 발견된 alias 한 줄씩: "name:source" (source=managed|external)
#   shell-rc.sh render <name> <config_dir>       → alias 라인만 출력 (수동 안내용)
#
# 자동 편집은 스킬이 만든 주석 블록(`# account-partition: <name>`)만 대상.
# 외부 alias는 list로 발견까지만, 수정 안 함.

set -uo pipefail

MARKER_PREFIX="# account-partition:"

render_alias_line() {
  local name="$1"
  local config_dir="$2"
  echo "alias claude-${name}=\"CLAUDE_CONFIG_DIR=${config_dir} command claude\""
}

render_block() {
  local name="$1"
  local config_dir="$2"
  echo "${MARKER_PREFIX} ${name}"
  render_alias_line "$name" "$config_dir"
}

add_alias() {
  local rc="$1"
  local name="$2"
  local config_dir="$3"

  # 기존 블록이 있으면 제거
  remove_alias "$rc" "$name"

  # 파일 끝에 추가 (개행 보장)
  if [[ -s "$rc" ]] && [[ $(tail -c 1 "$rc" | wc -l) -eq 0 ]]; then
    echo "" >> "$rc"
  fi
  render_block "$name" "$config_dir" >> "$rc"
}

remove_alias() {
  local rc="$1"
  local name="$2"

  # 주석 블록 + 그 다음 alias 라인 한 줄 삭제 (sed로 처리)
  # 매칭: '# account-partition: NAME' 라인과 그 다음 라인
  python3 - "$rc" "$name" <<'PYEOF'
import sys, re

rc_path = sys.argv[1]
name = sys.argv[2]
marker_re = re.compile(r'^# account-partition:\s*' + re.escape(name) + r'\s*$')

with open(rc_path, 'r') as f:
    lines = f.readlines()

new_lines = []
skip_next = False
for line in lines:
    if skip_next:
        skip_next = False
        continue
    if marker_re.match(line):
        skip_next = True  # 다음 라인(alias)도 삭제
        continue
    new_lines.append(line)

with open(rc_path, 'w') as f:
    f.writelines(new_lines)
PYEOF
}

list_aliases() {
  local rc="$1"
  [[ -f "$rc" ]] || return 0

  # managed: marker 다음 라인이 alias claude-NAME
  python3 - "$rc" <<'PYEOF'
import sys, re

rc_path = sys.argv[1]
managed_re = re.compile(r'^# account-partition:\s*(\S+)\s*$')
alias_re = re.compile(r'^\s*alias\s+claude-([A-Za-z0-9_-]+)\s*=')

with open(rc_path, 'r') as f:
    lines = f.readlines()

managed = set()
external = set()
i = 0
while i < len(lines):
    m = managed_re.match(lines[i])
    if m and i + 1 < len(lines):
        am = alias_re.match(lines[i+1])
        if am and am.group(1) == m.group(1):
            managed.add(m.group(1))
            i += 2
            continue
    a = alias_re.match(lines[i])
    if a:
        external.add(a.group(1))
    i += 1

# managed가 우선
for n in sorted(managed):
    print(f"{n}:managed")
for n in sorted(external - managed):
    print(f"{n}:external")
PYEOF
}

cmd="${1:-help}"
case "$cmd" in
  add)    add_alias "$2" "$3" "$4" ;;
  remove) remove_alias "$2" "$3" ;;
  list)   list_aliases "$2" ;;
  render) render_alias_line "$2" "$3" ;;
  *)
    echo "Usage: $0 {add|remove|list|render} ..." >&2
    exit 1
    ;;
esac
EOF
chmod +x scripts/shell-rc.sh
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

```bash
bash tests/unit/run.sh
```

Expected: 모든 assertion PASS

- [ ] **Step 5: Commit**

```bash
git add skills/account-partition/scripts/shell-rc.sh skills/account-partition/tests/unit/shell_rc_test.sh
git commit -m "feat(account-partition): shell-rc.sh (zshrc alias 발견·자동 편집)"
```

---

## Phase C — 안전장치 (safety.sh)

활성 세션 게이트, lockfile, 백업 유틸 등 모든 변경 작업이 공유 사용할 안전 인프라.

### Task C.1: safety.sh — 활성 세션 감지 + lockfile [TDD]

**Files:**
- Create: `skills/account-partition/scripts/safety.sh`
- Create: `skills/account-partition/tests/unit/safety_test.sh`

- [ ] **Step 1: 실패 테스트 작성**

```bash
cat > tests/unit/safety_test.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

sb=$(make_sandbox)
trap 'cleanup_sandbox "$sb"' EXIT

# lockfile 획득
mkdir -p "$sb/.claude-test"
bash "$SCRIPTS/safety.sh" lock "$sb/.claude-test" "$$" && {
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ lock 획득 성공"
} || {
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ lock 획득 실패"
}

assert_file_exists "$sb/.claude-test/.account-partition.lock"

# 두 번째 lock은 실패해야 함 (다른 PID)
if bash "$SCRIPTS/safety.sh" lock "$sb/.claude-test" "999999" 2>/dev/null; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 두 번째 lock이 성공 (실패해야 함)"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 두 번째 lock 거부 OK"
fi

# 같은 PID의 두 번째 lock은 idempotent (성공)
if bash "$SCRIPTS/safety.sh" lock "$sb/.claude-test" "$$"; then
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 같은 PID 재진입 OK (idempotent)"
else
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 같은 PID 재진입 거부됨"
fi

# unlock
bash "$SCRIPTS/safety.sh" unlock "$sb/.claude-test" "$$"
if [[ -f "$sb/.claude-test/.account-partition.lock" ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ unlock 후에도 lockfile 잔존"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ unlock 완료"
fi

# 백업 유틸
echo "test content" > "$sb/file.txt"
backup_path=$(bash "$SCRIPTS/safety.sh" backup "$sb/file.txt")
assert_file_exists "$backup_path"
assert_contains "$backup_path" ".bak." "백업 파일 이름에 .bak. 포함"
assert_eq "$(cat "$backup_path")" "test content" "백업 내용 보존"

print_summary
EOF
chmod +x tests/unit/safety_test.sh
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

- [ ] **Step 3: safety.sh 작성**

```bash
cat > scripts/safety.sh <<'EOF'
#!/usr/bin/env bash
# 안전장치 유틸: 활성 세션 감지, lockfile, 백업, 격리 보존.
# 사용:
#   safety.sh lock <config_dir> <pid>              → lockfile 획득 (다른 PID 점유 시 실패)
#   safety.sh unlock <config_dir> <pid>            → lockfile 해제 (같은 PID여야 함)
#   safety.sh check-active <config_dir>            → 해당 CONFIG_DIR을 점유한 claude 프로세스 있는지 (exit 0=있음, 1=없음)
#   safety.sh backup <path>                        → <path>.bak.<ts> 생성 후 백업 경로 출력
#   safety.sh quarantine <config_dir> <item_path>  → <config_dir>/.account-partition-quarantine/ 으로 이동, 경로 출력

set -uo pipefail

now_ts() {
  date +%Y%m%d-%H%M%S
}

lock_path() {
  echo "$1/.account-partition.lock"
}

acquire_lock() {
  local config_dir="$1"
  local pid="$2"
  local lock
  lock=$(lock_path "$config_dir")

  if [[ -f "$lock" ]]; then
    local existing
    existing=$(cat "$lock" 2>/dev/null || echo "")
    if [[ "$existing" == "$pid" ]]; then
      return 0  # idempotent
    fi
    # 다른 PID — 그 PID가 살아있는지 확인
    if [[ -n "$existing" ]] && kill -0 "$existing" 2>/dev/null; then
      echo "Error: lock held by PID $existing" >&2
      return 1
    fi
    # 좀비 lock — 정리하고 계속
    rm -f "$lock"
  fi

  mkdir -p "$config_dir"
  echo "$pid" > "$lock"
}

release_lock() {
  local config_dir="$1"
  local pid="$2"
  local lock
  lock=$(lock_path "$config_dir")

  if [[ -f "$lock" ]]; then
    local existing
    existing=$(cat "$lock")
    if [[ "$existing" == "$pid" ]]; then
      rm -f "$lock"
    else
      echo "Error: lock held by $existing, not $pid" >&2
      return 1
    fi
  fi
}

check_active_processes() {
  local config_dir="$1"
  # macOS: pgrep -f 로 claude 프로세스 검색 + 환경변수 매칭은 ps eww로
  # 활성 daemon은 daemon.lock 마커로 판별
  if [[ -f "$config_dir/daemon.lock" ]]; then
    local daemon_pid
    daemon_pid=$(python3 -c "
import json
try:
    d = json.load(open('$config_dir/daemon.status.json'))
    print(d.get('pid', ''))
except Exception:
    pass
")
    if [[ -n "$daemon_pid" ]] && kill -0 "$daemon_pid" 2>/dev/null; then
      echo "Active daemon: PID $daemon_pid (config: $config_dir)"
      return 0
    fi
  fi

  # 직접 claude 프로세스 검색 — 환경변수로 매칭 (macOS는 ps eww)
  while IFS= read -r pid; do
    local env_dir
    env_dir=$(ps eww -p "$pid" 2>/dev/null | grep -oE "CLAUDE_CONFIG_DIR=[^ ]+" | head -1 | cut -d= -f2)
    if [[ "$env_dir" == "$config_dir" ]]; then
      echo "Active claude process: PID $pid (config: $config_dir)"
      return 0
    fi
  done < <(pgrep -f 'claude' 2>/dev/null || true)

  return 1
}

backup_file() {
  local path="$1"
  [[ -e "$path" ]] || { echo "Error: $path not found" >&2; return 1; }
  local ts; ts=$(now_ts)
  local backup="${path}.bak.${ts}"
  cp -p "$path" "$backup"
  chmod 0600 "$backup" 2>/dev/null || true
  echo "$backup"
}

quarantine_item() {
  local config_dir="$1"
  local item_path="$2"
  local ts; ts=$(now_ts)
  local q_dir="$config_dir/.account-partition-quarantine"
  mkdir -p "$q_dir"

  local item_name
  item_name=$(basename "$item_path")
  local dest="$q_dir/${item_name}.${ts}"

  # 원자적 이동
  mv "$item_path" "$dest"
  echo "$dest"
}

cmd="${1:-help}"
case "$cmd" in
  lock)         acquire_lock "$2" "$3" ;;
  unlock)       release_lock "$2" "$3" ;;
  check-active) check_active_processes "$2" ;;
  backup)       backup_file "$2" ;;
  quarantine)   quarantine_item "$2" "$3" ;;
  *)
    echo "Usage: $0 {lock|unlock|check-active|backup|quarantine} ..." >&2
    exit 1
    ;;
esac
EOF
chmod +x scripts/safety.sh
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

- [ ] **Step 5: Commit**

```bash
git add skills/account-partition/scripts/safety.sh skills/account-partition/tests/unit/safety_test.sh
git commit -m "feat(account-partition): safety.sh (lockfile·활성 세션 감지·백업·격리 보존)"
```

---

## Phase D — Operation Plan 라이브러리

설계 §15의 단일 plan 모델 구현. plan은 JSON으로 표현, 동일 plan에서 render/dry-run/execute/rollback 모두 생성.

### Task D.1: plan-render.sh — plan → 사람이 읽을 텍스트 [TDD]

**Files:**
- Create: `skills/account-partition/scripts/plan-render.sh`
- Create: `skills/account-partition/tests/unit/plan_render_test.sh`

- [ ] **Step 1: plan JSON 스키마 정의**

Plan 객체 구조 (모든 plan 빌더·렌더·실행이 따를 계약):

```json
{
  "metadata": {
    "action": "add" | "edit" | "delete",
    "alias_name": "side",
    "config_dir": "/Users/gang/.claude-side",
    "shared_pool": "/Users/gang/.claude-shared",
    "timestamp": "20260526-130000"
  },
  "preconditions": [
    {"check": "no_active_session", "config_dir": "/Users/gang/.claude-side"},
    {"check": "dir_absent", "path": "/Users/gang/.claude-side"}
  ],
  "operations": [
    {"op": "create_dir", "path": "/Users/gang/.claude-side", "mode": "0700"},
    {"op": "create_symlink", "src": "/Users/gang/.claude-shared/plugins", "dst": "/Users/gang/.claude-side/plugins", "backup_if_exists": true},
    {"op": "append_block", "file": "/Users/gang/.zshrc", "marker": "# account-partition: side", "lines": ["alias claude-side=\"...\""], "backup": true}
  ],
  "rollback_hints": [
    {"op": "remove_dir", "path": "/Users/gang/.claude-side"},
    {"op": "restore_from_backup", "file": "/Users/gang/.zshrc"}
  ]
}
```

- [ ] **Step 2: 실패 테스트 작성**

```bash
cat > tests/unit/plan_render_test.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

# 샘플 plan
plan=$(cat <<JSON
{
  "metadata": {
    "action": "add",
    "alias_name": "side",
    "config_dir": "/Users/test/.claude-side",
    "shared_pool": "/Users/test/.claude-shared"
  },
  "operations": [
    {"op": "create_dir", "path": "/Users/test/.claude-side", "mode": "0700"},
    {"op": "create_symlink", "src": "/Users/test/.claude-shared/plugins", "dst": "/Users/test/.claude-side/plugins"},
    {"op": "create_symlink", "src": "/Users/test/.claude-shared/settings.json", "dst": "/Users/test/.claude-side/settings.json"},
    {"op": "append_block", "file": "/Users/test/.zshrc", "marker": "# account-partition: side", "lines": ["alias claude-side=\"CLAUDE_CONFIG_DIR=/Users/test/.claude-side command claude\""], "backup": true}
  ]
}
JSON
)

out=$(echo "$plan" | bash "$SCRIPTS/plan-render.sh")

echo "--- plan-render output ---"
echo "$out"
echo "---"

assert_contains "$out" "계정 추가" "헤더에 액션 표시"
assert_contains "$out" "claude-side" "alias 이름 표시"
assert_contains "$out" "생성" "create_dir → '생성'"
assert_contains "$out" "공유" "create_symlink → '공유'"
assert_contains "$out" "/Users/test/.claude-shared/plugins" "심볼릭 대상 경로 표시"
assert_contains "$out" "추가" "append_block → '추가'"
assert_contains "$out" "백업" "backup=true → 백업 안내"

print_summary
EOF
chmod +x tests/unit/plan_render_test.sh
```

- [ ] **Step 3: 테스트 실행해서 실패 확인**

- [ ] **Step 4: plan-render.sh 작성**

```bash
cat > scripts/plan-render.sh <<'EOF'
#!/usr/bin/env bash
# Plan JSON을 stdin으로 받아 사람이 읽을 텍스트로 변환.
set -uo pipefail

python3 <<'PYEOF'
import json, sys

plan = json.load(sys.stdin)
md = plan.get("metadata", {})
ops = plan.get("operations", [])

action_label = {
  "add": "계정 추가",
  "edit": "공유 항목 수정",
  "delete": "계정 연동 해제",
}.get(md.get("action", ""), md.get("action", ""))

alias = md.get("alias_name", "?")
print(f"다음 작업을 실행합니다 ({action_label} — claude-{alias}):")
print()

# 항목별 라벨 매핑 (디자인 §8과 일치)
ITEM_LABEL = {
  "plugins": "플러그인",
  "skills": "스킬",
  "commands": "슬래시 명령",
  "agents": "서브에이전트",
  "CLAUDE.md": "글로벌 인스트럭션",
  "settings.json": "전역 설정",
}

def label_for_path(p):
  base = p.rstrip("/").rsplit("/", 1)[-1]
  return ITEM_LABEL.get(base, base)

for op in ops:
  kind = op.get("op")
  if kind == "create_dir":
    print(f"  생성       {op['path']}")
  elif kind == "remove_dir":
    print(f"  제거       {op['path']}")
  elif kind == "create_symlink":
    label = label_for_path(op["src"])
    backup_note = " (기존 파일 백업)" if op.get("backup_if_exists") else ""
    print(f"  공유       {label:14s} → {op['src']}{backup_note}")
  elif kind == "remove_symlink":
    print(f"  공유 해제  {op['dst']}")
  elif kind == "copy":
    print(f"  사본 생성  {op['src']} → {op['dst']}")
  elif kind == "append_block":
    backup_note = " (백업: yes)" if op.get("backup") else ""
    print(f"  추가       {op['file']}{backup_note}")
    for line in op.get("lines", []):
      print(f"             {line}")
  elif kind == "move":
    print(f"  이동       {op['src']} → {op['dst']}")
  elif kind == "quarantine":
    print(f"  격리 보존  {op['path']} (충돌 사본 임시 보존)")
  else:
    print(f"  ?          {kind}: {op}")

print()
print("진행할까요? (예 / 아니오 / 명령 출력만)")
PYEOF
EOF
chmod +x scripts/plan-render.sh
```

- [ ] **Step 5: 테스트 실행해서 통과 확인**

- [ ] **Step 6: Commit**

```bash
git add skills/account-partition/scripts/plan-render.sh skills/account-partition/tests/unit/plan_render_test.sh
git commit -m "feat(account-partition): plan-render.sh (plan → 사람 읽을 텍스트)"
```

---

### Task D.2: plan-shell-out.sh — plan → 셸 명령 시퀀스 (드라이런) [TDD]

**Files:**
- Create: `skills/account-partition/scripts/plan-shell-out.sh`
- Create: `skills/account-partition/tests/unit/plan_shell_out_test.sh`

- [ ] **Step 1: 실패 테스트 작성**

```bash
cat > tests/unit/plan_shell_out_test.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

plan='{"metadata":{"action":"add","alias_name":"side"},"operations":[{"op":"create_dir","path":"/tmp/test-side","mode":"0700"},{"op":"create_symlink","src":"/tmp/shared/plugins","dst":"/tmp/test-side/plugins"},{"op":"append_block","file":"/tmp/.zshrc","marker":"# account-partition: side","lines":["alias claude-side=\"x\""],"backup":true}]}'

out=$(echo "$plan" | bash "$SCRIPTS/plan-shell-out.sh")

echo "--- plan-shell-out output ---"
echo "$out"
echo "---"

assert_contains "$out" "mkdir -p /tmp/test-side" "mkdir 명령"
assert_contains "$out" "chmod 0700 /tmp/test-side" "chmod 명령"
assert_contains "$out" "ln -s /tmp/shared/plugins /tmp/test-side/plugins" "symlink 명령"
assert_contains "$out" "cp -p /tmp/.zshrc" "백업 명령"
assert_contains "$out" "alias claude-side" "alias 본문"

print_summary
EOF
chmod +x tests/unit/plan_shell_out_test.sh
```

- [ ] **Step 2: 실패 확인**

- [ ] **Step 3: plan-shell-out.sh 작성**

```bash
cat > scripts/plan-shell-out.sh <<'EOF'
#!/usr/bin/env bash
# Plan JSON을 stdin으로 받아 사용자가 직접 실행 가능한 셸 명령 시퀀스로 변환.
set -uo pipefail

python3 <<'PYEOF'
import json, sys, shlex

plan = json.load(sys.stdin)
ops = plan.get("operations", [])

def sh(s):
  return shlex.quote(s)

print("# account-partition: 드라이런 — 다음 명령을 직접 실행하면 동일한 결과")
print("set -e")
print()

for op in ops:
  kind = op.get("op")
  if kind == "create_dir":
    print(f"mkdir -p {sh(op['path'])}")
    if op.get("mode"):
      print(f"chmod {op['mode']} {sh(op['path'])}")
  elif kind == "remove_dir":
    print(f"rm -rf {sh(op['path'])}")
  elif kind == "create_symlink":
    if op.get("backup_if_exists"):
      # 셸로 표현 가능한 idempotent 백업
      print(f"if [ -e {sh(op['dst'])} ] && [ ! -L {sh(op['dst'])} ]; then cp -p {sh(op['dst'])} {sh(op['dst'])}.bak.$(date +%Y%m%d-%H%M%S); rm {sh(op['dst'])}; fi")
    print(f"ln -s {sh(op['src'])} {sh(op['dst'])}")
  elif kind == "remove_symlink":
    print(f"rm {sh(op['dst'])}")
  elif kind == "copy":
    print(f"cp -p {sh(op['src'])} {sh(op['dst'])}")
  elif kind == "move":
    print(f"mv {sh(op['src'])} {sh(op['dst'])}")
  elif kind == "append_block":
    if op.get("backup"):
      print(f"cp -p {sh(op['file'])} {sh(op['file'])}.bak.$(date +%Y%m%d-%H%M%S)")
    marker = op.get("marker", "")
    print(f"echo {sh(marker)} >> {sh(op['file'])}")
    for line in op.get("lines", []):
      print(f"echo {sh(line)} >> {sh(op['file'])}")
  elif kind == "quarantine":
    # quarantine은 safety.sh에 의존 — 셸로 풀어 표현
    print(f"# quarantine: {op['path']} → {op.get('config_dir', '')}/.account-partition-quarantine/")
    print(f"mkdir -p {sh(op.get('config_dir', '') + '/.account-partition-quarantine')}")
    print(f"mv {sh(op['path'])} {sh(op.get('config_dir', '') + '/.account-partition-quarantine/')}")
  else:
    print(f"# (unknown op: {kind})")
PYEOF
EOF
chmod +x scripts/plan-shell-out.sh
```

- [ ] **Step 4: 통과 확인**

- [ ] **Step 5: Commit**

```bash
git add skills/account-partition/scripts/plan-shell-out.sh skills/account-partition/tests/unit/plan_shell_out_test.sh
git commit -m "feat(account-partition): plan-shell-out.sh (드라이런 — 셸 명령 시퀀스)"
```

---

### Task D.3: plan-execute.sh — plan 실행 엔진 [TDD]

**Files:**
- Create: `skills/account-partition/scripts/plan-execute.sh`
- Create: `skills/account-partition/tests/unit/plan_execute_test.sh`

- [ ] **Step 1: 실패 테스트 작성**

```bash
cat > tests/unit/plan_execute_test.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"

sb=$(make_sandbox)
trap 'cleanup_sandbox "$sb"' EXIT

# 시나리오: create_dir + create_symlink + append_block
mkdir -p "$sb/shared"
echo "shared-content" > "$sb/shared/settings.json"

plan=$(cat <<JSON
{
  "metadata": {"action":"add","alias_name":"test","config_dir":"$sb/.claude-test"},
  "operations": [
    {"op":"create_dir","path":"$sb/.claude-test","mode":"0700"},
    {"op":"create_symlink","src":"$sb/shared/settings.json","dst":"$sb/.claude-test/settings.json"},
    {"op":"append_block","file":"$sb/.zshrc","marker":"# account-partition: test","lines":["alias claude-test=\"x\""],"backup":false}
  ]
}
JSON
)
touch "$sb/.zshrc"

# 실행 (PLAN_DIR로 상태 파일 위치 지정)
echo "$plan" | PLAN_DIR="$sb" bash "$SCRIPTS/plan-execute.sh"

# 결과 검증
assert_file_exists "$sb/.claude-test"
assert_symlink_target "$sb/.claude-test/settings.json" "$sb/shared/settings.json"

content=$(cat "$sb/.zshrc")
assert_contains "$content" "# account-partition: test" "marker 추가"
assert_contains "$content" "alias claude-test" "alias 추가"

# 상태 파일 존재
assert_file_exists "$sb/.account-partition-state.json"

print_summary
EOF
chmod +x tests/unit/plan_execute_test.sh
```

- [ ] **Step 2: 실패 확인**

- [ ] **Step 3: plan-execute.sh 작성**

```bash
cat > scripts/plan-execute.sh <<'EOF'
#!/usr/bin/env bash
# Plan JSON을 stdin으로 받아 실제 실행. 단계별로 상태 파일에 진행 상황 기록.
# 사용:
#   echo "$plan" | plan-execute.sh
# 환경변수:
#   PLAN_DIR  상태 파일 위치 (기본: SHARED_POOL 또는 $HOME)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLAN_DIR="${PLAN_DIR:-$HOME}"
STATE_FILE="$PLAN_DIR/.account-partition-state.json"

plan=$(cat)
echo "$plan" > "$STATE_FILE"

python3 - <<PYEOF
import json, os, sys, subprocess, shlex
plan = json.loads('''$plan''')
ops = plan.get("operations", [])
completed = []

def run(cmd):
    print(f"  $ {' '.join(shlex.quote(c) for c in cmd)}")
    subprocess.run(cmd, check=True)

try:
    for i, op in enumerate(ops):
        kind = op["op"]
        if kind == "create_dir":
            os.makedirs(op["path"], exist_ok=True)
            if "mode" in op:
                os.chmod(op["path"], int(op["mode"], 8))
        elif kind == "remove_dir":
            run(["rm", "-rf", op["path"]])
        elif kind == "create_symlink":
            dst = op["dst"]
            if os.path.exists(dst) or os.path.islink(dst):
                if op.get("backup_if_exists"):
                    import datetime
                    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
                    backup = f"{dst}.bak.{ts}"
                    run(["cp", "-Rp", dst, backup])
                run(["rm", "-rf", dst])
            os.symlink(op["src"], dst)
        elif kind == "remove_symlink":
            if os.path.islink(op["dst"]):
                os.unlink(op["dst"])
        elif kind == "copy":
            run(["cp", "-Rp", op["src"], op["dst"]])
        elif kind == "move":
            run(["mv", op["src"], op["dst"]])
        elif kind == "append_block":
            if op.get("backup") and os.path.exists(op["file"]):
                import datetime
                ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
                run(["cp", "-p", op["file"], f"{op['file']}.bak.{ts}"])
            # 같은 marker 블록 idempotent — sh-rc.sh 로직 재사용
            subpro