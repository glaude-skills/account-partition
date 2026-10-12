#!/usr/bin/env bash
# 모든 발견된 계정에 대해 공유/격리 매트릭스 출력.
# 환경변수:
#   HOME         (기본: $HOME)
#   SHARED_POOL  (기본: $HOME/.claude-shared)
#   SCRIPTS_DIR  (기본: 자신과 같은 디렉토리) — discover.sh 위치
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/platform.sh"

HOME="${HOME:?HOME is required}"
SHARED_POOL="${SHARED_POOL:-$HOME/.claude-shared}"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="${SCRIPTS_DIR:-$SELF_DIR}"

HOME_ENV="$HOME" SHARED_POOL_ENV="$SHARED_POOL" SCRIPTS_DIR_ENV="$SCRIPTS_DIR" python3 - <<'PYEOF'
import os, subprocess, json, sys, shutil
sys.path.insert(0, os.path.dirname(os.environ["AP_LIB"]))
import aplib
from aplib import npath

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

def print_shell_defs():
    # 셸 명령 정의 (registry + 외부 정의) — v0.5
    try:
        summ = aplib.accounts_summary(os.path.join(npath(SHARED_POOL), "accounts.json"))
    except Exception as e:
        summ = None
        print()
        print(f"  (셸 정의 조회 실패: {e})")
    if summ:
        reg = summ["registry"]["accounts"]
        print()
        print()
        print("셸 명령 정의 (스킬 관리)")
        print("─" * 75)
        if not reg:
            print("  (없음)")
        for name, a in sorted(reg.items()):
            mode = "토큰만 분리" if a.get("mode") == "token-only" else "일반"
            tok = a.get("token_dir") or "(config와 같음)"
            kinds = ",".join(sorted({t["kind"] for t in a.get("targets", [])})) or "수동"
            print(f"  claude-{name:<12} {mode:<8} config={a.get('config_dir')}  토큰={tok}  셸={kinds}")
        ext = [e for e in summ["externals"] if not e["in_registry"]]
        if ext:
            print()
            print("셸 명령 정의 (외부 — 가져오기 가능: /account-partition:adopt)")
            print("─" * 75)
            for e in ext:
                for v in e["variants"]:
                    d = v["definition"]
                    srcs = ",".join(sorted({s["kind"] for s in v["sources"]}))
                    print(f"  claude-{e['name']:<12} config={d['config_dir']}  토큰={d['token_dir'] or '(config와 같음)'}  출처={srcs}")
                if len(e["variants"]) > 1:
                    print(f"  ⚠ claude-{e['name']} 정의가 셸마다 다릅니다 — 실행하는 셸에 따라 다른 계정 구성이 뜹니다.")
                for u in e["unparseable"]:
                    print(f"  ? claude-{e['name']} 해석 불가: {u['file']} ({u['reason']})")

# 계정 목록
try:
    res = subprocess.run(
        [aplib.bash_exe(), os.path.join(npath(SCRIPTS_DIR), "discover.sh"), "list-dirs"],
        env={**os.environ, "HOME": HOME, "SHARED_POOL": SHARED_POOL},
        capture_output=True, text=True, check=True,
    )
    dirs = [d for d in res.stdout.strip().split("\n") if d]
except subprocess.CalledProcessError as e:
    print("Error: discover.sh failed: " + e.stderr, file=sys.stderr)
    sys.exit(1)

if not dirs:
    print("등록된 Claude 계정이 없습니다.")
    print_shell_defs()
    sys.exit(0)

# 각 계정 메타 수집
accounts = []
for d in dirs:
    try:
        res = subprocess.run(
            [aplib.bash_exe(), os.path.join(npath(SCRIPTS_DIR), "discover.sh"), "meta", d],
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
            st_env = {**os.environ, "CLAUDE_CONFIG_DIR": npath(d)}
            st_env.pop("CLAUDE_SECURESTORAGE_CONFIG_DIR", None)
            status_res = subprocess.run(
                [shutil.which("claude") or "claude", "auth", "status"],
                env=st_env,
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
    path = os.path.join(npath(d), item)
    shared_pool = npath(shared_pool)
    if not (os.path.exists(path) or aplib.is_link(path)):
        return "─"
    if aplib.is_link(path):
        target = os.readlink(path)
        # 절대 경로로 정규화하여 비교
        abs_target = os.path.realpath(target) if not os.path.isabs(target) else target
        sp_real = os.path.realpath(shared_pool) if os.path.exists(shared_pool) else shared_pool
        if aplib._norm_cmp(target).startswith(aplib._norm_cmp(shared_pool)) or aplib._norm_cmp(abs_target).startswith(aplib._norm_cmp(sp_real)):
            return "● 공유"
        return "링크→외부"
    return "자체"

def status_for_forced(d, item, shared_pool):
    """settings.json 같은 격리 강제 항목 — 외부에서 공유 중이면 ⚠ 경고"""
    path = os.path.join(npath(d), item)
    shared_pool = npath(shared_pool)
    if aplib.is_link(path):
        target = os.readlink(path)
        abs_target = os.path.realpath(target) if not os.path.isabs(target) else target
        sp_real = os.path.realpath(shared_pool) if os.path.exists(shared_pool) else shared_pool
        if aplib._norm_cmp(target).startswith(aplib._norm_cmp(shared_pool)) or aplib._norm_cmp(abs_target).startswith(aplib._norm_cmp(sp_real)):
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

print_shell_defs()
PYEOF
