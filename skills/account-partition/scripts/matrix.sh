#!/usr/bin/env bash
# 모든 발견된 계정에 대해 공유/격리 매트릭스 출력.
# 환경변수:
#   HOME         (기본: $HOME)
#   SHARED_POOL  (기본: $HOME/.claude-shared)
#   SCRIPTS_DIR  (기본: 자신과 같은 디렉토리) — discover.sh 위치
set -uo pipefail

HOME="${HOME:?HOME is required}"
SHARED_POOL="${SHARED_POOL:-$HOME/.claude-shared}"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="${SCRIPTS_DIR:-$SELF_DIR}"

HOME_ENV="$HOME" SHARED_POOL_ENV="$SHARED_POOL" SCRIPTS_DIR_ENV="$SCRIPTS_DIR" python3 - <<'PYEOF'
import os, subprocess, json, sys

HOME = os.environ["HOME_ENV"]
SHARED_POOL = os.environ["SHARED_POOL_ENV"]
SCRIPTS_DIR = os.environ["SCRIPTS_DIR_ENV"]

TOGGLEABLE = [
    ("플러그인", "plugins"),
    ("스킬", "skills"),
    ("슬래시 명령", "commands"),
    ("서브에이전트", "agents"),
    ("글로벌 인스트럭션", "CLAUDE.md"),
]
FORCED_ISOLATED = [
    ("전역 설정", "settings.json"),
]

# 계정 목록
try:
    res = subprocess.run(
        ["bash", os.path.join(SCRIPTS_DIR, "discover.sh"), "list-dirs"],
        env={**os.environ, "HOME": HOME, "SHARED_POOL": SHARED_POOL},
        capture_output=True, text=True, check=True,
    )
    dirs = [d for d in res.stdout.strip().split("\n") if d]
except subprocess.CalledProcessError as e:
    print("Error: discover.sh failed: " + e.stderr, file=sys.stderr)
    sys.exit(1)

if not dirs:
    print("등록된 Claude 계정이 없습니다.")
    sys.exit(0)

# 각 계정 메타 수집
accounts = []
for d in dirs:
    try:
        res = subprocess.run(
            ["bash", os.path.join(SCRIPTS_DIR, "discover.sh"), "meta", d],
            capture_output=True, text=True, check=True,
        )
        meta = json.loads(res.stdout)
    except Exception:
        meta = {"dir": d, "alias": os.path.basename(d).lstrip("."), "email": ""}
    accounts.append(meta)

# 헤더
print("연동된 Claude 계정 (" + str(len(accounts)) + ")                       공유 보관소: " + SHARED_POOL)
print("─" * 75)
print()
print("  명령어           계정 이메일                  로그인 상태")
print("  " + "─" * 16 + "  " + "─" * 27 + "  " + "─" * 12)

for meta in accounts:
    alias = meta.get("alias", "")
    email = meta.get("email") or ""
    login = "—"

    # claude auth status cross-check (SKIP_AUTH_STATUS=1이면 생략)
    if not os.environ.get("SKIP_AUTH_STATUS"):
        d = meta.get("dir", "")
        try:
            status_res = subprocess.run(
                ["claude", "auth", "status"],
                env={**os.environ, "CLAUDE_CONFIG_DIR": d},
                capture_output=True, text=True, timeout=5,
            )
            if status_res.returncode == 0:
                status_data = json.loads(status_res.stdout)
                if status_data.get("loggedIn"):
                    login = "✓"
                    if not email:
                        email = status_data.get("email", "")
        except Exception:
            pass

    # fallback: .claude.json의 email 유무로 판별
    if login == "—" and meta.get("email"):
        login = "✓"
    if not email:
        email = "—"
    # alias가 이미 "claude-xxx" 형태인 경우도 있고, 그냥 디렉토리 basename인 경우도 있음
    if alias.startswith("claude-") or alias.startswith("claude "):
        name_disp = alias
    else:
        name_disp = "claude-" + alias
    print("  " + name_disp[:16].ljust(16) + " " + email[:27].ljust(27) + "  " + login)

print()
print()
print("공유 / 격리 매트릭스")
print("─" * 75)
print()

col_w = 18

# 컬럼 헤더 — 계정 디렉토리 basename (점 제거)
header = " " * 28
for meta in accounts:
    alias = meta.get("alias", "")
    # alias는 discover.sh가 이미 basename에서 점 제거한 형태로 반환
    # "claude (기본)" 같은 경우도 있음
    col_label = alias
    header += col_label[:col_w].center(col_w)
print(header)
print(" " * 28 + (("─" * (col_w - 2)) + "  ") * len(accounts))

def status_for_toggleable(d, item, shared_pool):
    path = os.path.join(d, item)
    if not (os.path.exists(path) or os.path.islink(path)):
        return "─"
    if os.path.islink(path):
        target = os.readlink(path)
        # 절대 경로로 정규화하여 비교
        abs_target = os.path.realpath(target) if not os.path.isabs(target) else target
        sp_real = os.path.realpath(shared_pool) if os.path.exists(shared_pool) else shared_pool
        if target.startswith(shared_pool) or abs_target.startswith(sp_real):
            return "● 공유"
        return "링크→외부"
    return "자체"

def status_for_forced(d, item, shared_pool):
    """settings.json 같은 격리 강제 항목 — 외부에서 공유 중이면 ⚠ 경고"""
    path = os.path.join(d, item)
    if os.path.islink(path):
        target = os.readlink(path)
        abs_target = os.path.realpath(target) if not os.path.isabs(target) else target
        sp_real = os.path.realpath(shared_pool) if os.path.exists(shared_pool) else shared_pool
        if target.startswith(shared_pool) or abs_target.startswith(sp_real):
            return "⚠ 공유"
    if os.path.exists(path):
        return "격리"
    return "─"

# 토글 가능 row
for label, item in TOGGLEABLE:
    line = "  " + label[:24].ljust(24)
    for meta in accounts:
        d = meta.get("dir", "")
        s = status_for_toggleable(d, item, SHARED_POOL)
        line += s.center(col_w)
    print(line)

print(" " * 28 + (("─" * (col_w - 2)) + "  ") * len(accounts))

# 격리 강제 row
for label, item in FORCED_ISOLATED:
    line = "  " + label[:24].ljust(24)
    for meta in accounts:
        d = meta.get("dir", "")
        s = status_for_forced(d, item, SHARED_POOL)
        line += s.center(col_w)
    print(line)

print()
print("  범례:")
print("    ● 공유    공유 보관소와 연결되어 다른 계정과 같은 실체 사용")
print("    자체      이 계정만의 사본 보유")
print("    격리      격리 강제 항목 (디자인상 공유 불가)")
print("    ⚠ 공유   격리 강제 항목인데 외부에서 공유 중 — 시크릿 노출 위험")
print("    ─         해당 항목이 디스크에 없음")
PYEOF
