#!/usr/bin/env bash
# Plan JSON (stdin)을 사용자가 직접 실행 가능한 셸 명령 시퀀스로 변환.
# '명령 출력만' 옵션에서 사용.
set -uo pipefail

# Python heredoc이 stdin 선점하므로 먼저 capture
PLAN_JSON=$(cat)
export PLAN_JSON

python3 <<'PYEOF'
import json, os, sys, shlex

try:
    plan = json.loads(os.environ['PLAN_JSON'])
except Exception as e:
    print(f"Error: invalid plan JSON: {e}", file=sys.stderr)
    sys.exit(1)

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
            print(f"if [ -e {sh(op['dst'])} ] && [ ! -L {sh(op['dst'])} ]; then cp -Rp {sh(op['dst'])} {sh(op['dst'])}.bak.$(date +%Y%m%d-%H%M%S)-$$; rm -rf {sh(op['dst'])}; fi")
        print(f"ln -s {sh(op['src'])} {sh(op['dst'])}")
    elif kind == "remove_symlink":
        print(f"rm {sh(op['dst'])}")
    elif kind == "copy":
        print(f"cp -Rp {sh(op['src'])} {sh(op['dst'])}")
    elif kind == "move":
        print(f"mv {sh(op['src'])} {sh(op['dst'])}")
    elif kind == "append_block":
        if op.get("backup"):
            print(f"cp -p {sh(op['file'])} {sh(op['file'])}.bak.$(date +%Y%m%d-%H%M%S)-$$")
        marker = op.get("marker", "")
        print(f"echo {sh(marker)} >> {sh(op['file'])}")
        for line in op.get("lines", []):
            print(f"echo {sh(line)} >> {sh(op['file'])}")
    elif kind == "quarantine":
        cfg = op.get('config_dir', '')
        q_dir = cfg + '/.account-partition-quarantine'
        print(f"mkdir -p {sh(q_dir)}")
        name = op['path'].rsplit('/', 1)[-1]
        print(f"mv {sh(op['path'])} {sh(q_dir + '/' + name + '.$(date +%Y%m%d-%H%M%S)-$$')}")
    elif kind == "auth_logout":
        cfg = op["config_dir"]
        print(f"CLAUDE_CONFIG_DIR={sh(cfg)} claude auth logout")
    elif kind == "remove_block":
        marker = op.get("marker", "")
        name = marker.split(":", 1)[1].strip() if ":" in marker else ""
        f = op.get("file", "")
        print(f"# marker '{marker}' 블록 제거 ({f})")
        print(f"bash \"$SCRIPTS/shell-rc.sh\" remove {sh(f)} {sh(name)}")
    elif kind == "archive_dir":
        src = op["src"]
        parent = os.path.dirname(src) or "."
        base = os.path.basename(src)
        dest_pat = src + ".removed.$(date +%Y%m%d-%H%M%S)-$$.tar.gz"
        print(f"tar czf {sh(dest_pat)} -C {sh(parent)} {sh(base)}")
        if op.get("remove_after"):
            print(f"rm -rf {sh(src)}")
    else:
        print(f"# (unknown op: {kind})")
PYEOF
