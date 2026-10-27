#!/usr/bin/env bash
# ap_attach.py: 세션을 띄운 토큰 폴더와 지금 계정 토큰 폴더를 비교해 attach 또는 stop + --resume.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"
source "$SCRIPTS/platform.sh"

sb=$(make_sandbox)
trap 'cleanup_sandbox "$sb"' EXIT
winp() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }
CFG="$(winp "$sb/cfg")"
WORK="$(winp "$sb/work")"
mkdir -p "$sb/cfg/daemon" "$sb/work"

job() {  # job <short> <name> <token_dir 또는 빈 값>
  mkdir -p "$sb/cfg/jobs/$1"
  python3 - "$(winp "$sb/cfg/jobs/$1/state.json")" "$1" "$2" "$3" "$WORK" <<'EOF'
import json, sys
path, short, name, tok, cwd = sys.argv[1:]
d = {"daemonShort": short, "sessionId": short + "-0000-4000-8000-000000000000", "name": name,
     "cwd": cwd, "respawnFlags": ["--name", name, "--model", "haiku"],
     "providerEnv": {"CLAUDE_SECURESTORAGE_CONFIG_DIR": tok} if tok else {}}
json.dump(d, open(path, "w", encoding="utf-8"))
EOF
}
roster() { python3 -c "import json,sys; json.dump({'workers': {k: {} for k in sys.argv[2:]}}, open(sys.argv[1], 'w'))" "$(winp "$sb/cfg/daemon/roster.json")" "$@"; }

job aaaa1111 probe-alpha "$CFG-tok-a"
job bbbb2222 probe-beta ""
job cccc3333 shared-x "$CFG-tok-a"
job dddd4444 shared-y "$CFG-tok-a"
roster aaaa1111

# run <내 토큰 폴더 또는 빈 값> <입력> <인자...>  → "rc|호출1;호출2"
run() {
  python3 - "$SCRIPTS" "$CFG" "$@" <<'EOF'
import os, sys
sys.path.insert(0, sys.argv[1])
import ap_attach as m
cfg, tok, answer, args = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:]
calls = []
def fake_call(cmd, cwd=None):
    calls.append(" ".join(cmd[1:]) + (" @cwd" if cwd else ""))
    return 0
m.subprocess.call = fake_call
m.shutil.which = lambda *a, **k: "claude"
import builtins
builtins.input = lambda *_: answer
env = {"CLAUDE_CONFIG_DIR": cfg}
if tok:
    env["CLAUDE_SECURESTORAGE_CONFIG_DIR"] = tok
sys.stdout = open(os.devnull, "w")
rc = m.main(args, env)
sys.stdout = sys.__stdout__
print(f"{rc}|" + ";".join(calls))
EOF
}

echo "── 같은 토큰: 그대로 attach"
assert_eq "$(run "$CFG-tok-a" "" attach aaaa1111)" "0|attach aaaa1111" "id 로 지정, 토큰 같음"
assert_eq "$(run "$CFG-tok-a" "" attach alpha)" "0|attach alpha" "이름 일부로 지정"
assert_eq "$(run "" "" attach bbbb2222)" "0|attach bbbb2222" "토큰 지정 없음끼리 (config 폴더 기준)"

echo "── 다른 토큰"
assert_eq "$(run "$CFG-tok-b" "y" attach aaaa1111)" \
  "0|stop aaaa1111;--resume aaaa1111-0000-4000-8000-000000000000 --name probe-alpha --model haiku @cwd" \
  "실행 중 + y: stop 뒤 세션 폴더에서 저장 옵션으로 --resume"
assert_eq "$(run "$CFG-tok-b" "n" attach aaaa1111)" "1|" "실행 중 + n: 아무것도 안 함"
assert_eq "$(run "$CFG-tok-b" "" attach bbbb2222)" \
  "0|--resume bbbb2222-0000-4000-8000-000000000000 --name probe-beta --model haiku @cwd" \
  "멈춘 세션: 묻지 않고 --resume"

echo "── 지정 실패"
assert_eq "$(run "$CFG-tok-b" "" attach shared)" "1|" "이름이 여러 세션에 걸리면 중단"
assert_eq "$(run "$CFG-tok-b" "" attach zzzz9999)" "0|attach zzzz9999" "모르는 세션은 claude attach 에 맡김"
assert_eq "$(run "$CFG-tok-b" "" logs aaaa1111)" "0|logs aaaa1111" "attach 아닌 명령은 그대로"

print_summary
