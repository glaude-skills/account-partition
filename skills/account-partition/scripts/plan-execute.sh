#!/usr/bin/env bash
# Plan JSON (stdin)을 실제로 실행. 단계별로 상태 파일에 진행 기록.
# 사용: echo "$plan_json" | PLAN_DIR=... SCRIPTS_DIR=... plan-execute.sh
# 환경변수:
#   PLAN_DIR    상태 파일 위치 (기본: $HOME)
#   SCRIPTS_DIR shell-rc.sh / aplib.py 위치 (기본: 이 스크립트와 같은 디렉토리)
#
# 성공 시 상태 파일 정리. 실패 시 보존 (rollback이 읽음). exit code:
#   0: 성공
#   1: 사용 오류 (잘못된 JSON 등)
#   2: 부분 실행 후 실패 (상태 파일 보존됨)
#
# 멀티 OS: 경로는 aplib.npath 로 네이티브 변환, Windows 디렉토리 링크는 junction,
# 링크 제거는 링크만 걷어낸다 (junction 안 내용 보존). 아카이브는 Python tarfile.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/platform.sh"

PLAN_DIR="${PLAN_DIR:-$HOME}"
STATE_FILE="$PLAN_DIR/.account-partition-state.json"

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPTS_DIR:-$_SELF_DIR}"

PLAN_JSON=$(cat)

if ! echo "$PLAN_JSON" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  echo "Error: invalid plan JSON" >&2
  exit 1
fi

mkdir -p "$PLAN_DIR"

export PLAN_JSON_ENV="$PLAN_JSON"
export STATE_FILE_ENV="$STATE_FILE"
export SCRIPTS_DIR_ENV="$SCRIPTS_DIR"

python3 <<'PYEOF'
import json, os, sys, shutil, subprocess, tarfile

sys.path.insert(0, os.path.dirname(os.environ["AP_LIB"]))
import aplib
from aplib import npath

plan = json.loads(os.environ['PLAN_JSON_ENV'])
state_file = npath(os.environ['STATE_FILE_ENV'])
ops = plan.get("operations", [])

with open(state_file, "w", encoding="utf-8") as f:
    json.dump(plan, f, ensure_ascii=False, indent=2)

completed = []
completed_ops = []


def archive(src, dest):
    """링크는 따라가지 않고 링크로 보관 (junction 포함)."""
    base = os.path.basename(src.rstrip("/\\"))
    with tarfile.open(dest, "w:gz") as tf:
        def add(path, arc):
            if aplib.is_link(path):
                ti = tarfile.TarInfo(arc)
                ti.type = tarfile.SYMTYPE
                try:
                    ti.linkname = os.readlink(path)
                except OSError:
                    ti.linkname = ""
                tf.addfile(ti)
            elif os.path.isdir(path):
                tf.add(path, arcname=arc, recursive=False)
                for entry in sorted(os.listdir(path)):
                    add(os.path.join(path, entry), arc + "/" + entry)
            else:
                tf.add(path, arcname=arc, recursive=False)
        add(src, base)


try:
    for i, op in enumerate(ops):
        kind = op["op"]

        if kind == "create_dir":
            p = npath(op["path"])
            os.makedirs(p, exist_ok=True)
            if "mode" in op:
                os.chmod(p, int(op["mode"], 8))

        elif kind == "remove_dir":
            aplib.remove_tree(op["path"])

        elif kind == "create_symlink":
            src, dst = npath(op["src"]), npath(op["dst"])
            if not os.path.exists(src):
                raise FileNotFoundError(f"symlink source does not exist: {src}")
            if os.path.lexists(dst):
                if op.get("backup_if_exists"):
                    if aplib.is_link(dst):
                        op["_backup_link"] = os.readlink(dst)
                    else:
                        backup = f"{dst}.bak.{aplib.now_ts()}"
                        if os.path.isdir(dst):
                            shutil.copytree(dst, backup, symlinks=True)
                        else:
                            shutil.copy2(dst, backup)
                        op["_backup_path"] = backup
                aplib.remove_tree(dst)
            op["_link_type"] = aplib.make_link(src, dst)

        elif kind == "remove_symlink":
            if aplib.is_link(op["dst"]):
                aplib.remove_link(op["dst"])

        elif kind == "copy":
            src, dst = npath(op["src"]), npath(op["dst"])
            if os.path.isdir(src):
                shutil.copytree(src, dst, symlinks=True)
            else:
                shutil.copy2(src, dst)

        elif kind == "move":
            shutil.move(npath(op["src"]), npath(op["dst"]))

        elif kind == "append_block":
            f_path = op["file"]
            marker = op.get("marker", "")
            if op.get("backup") and os.path.exists(npath(f_path)):
                shutil.copy2(npath(f_path), f"{npath(f_path)}.bak.{aplib.now_ts()}")
            if marker.startswith("# account-partition:"):
                aplib.block_remove(f_path, marker.split(":", 1)[1].strip())
            with open(npath(f_path), "a", encoding="utf-8", newline="\n") as fh:
                fh.write(marker + "\n")
                for line in op.get("lines", []):
                    fh.write(line + "\n")

        elif kind == "quarantine":
            cfg = npath(op.get("config_dir", ""))
            q = os.path.join(cfg, ".account-partition-quarantine")
            os.makedirs(q, exist_ok=True)
            p = npath(op["path"])
            if os.path.lexists(p):
                shutil.move(p, os.path.join(q, f"{os.path.basename(p)}.{aplib.now_ts()}"))

        elif kind == "auth_logout":
            cfg = npath(op["config_dir"])
            env = {**os.environ, "CLAUDE_CONFIG_DIR": cfg}
            env.pop("CLAUDE_SECURESTORAGE_CONFIG_DIR", None)
            exe = shutil.which("claude") or "claude"
            res = subprocess.run([exe, "auth", "logout"], env=env, capture_output=True, text=True)
            if res.returncode == 0:
                print(f"  auth_logout OK: {res.stdout.strip()[:80]}")
            else:
                print(f"  auth_logout 경고 (계속 진행): {res.stderr.strip()[:120]}")

        elif kind == "remove_block":
            name = op.get("name")
            if not name:
                marker = op.get("marker", "")
                name = marker.split(":", 1)[1].strip() if ":" in marker else ""
            if not name:
                raise RuntimeError(f"remove_block: name 없음 ({op})")
            if os.path.exists(npath(op["file"])):
                if op.get("backup"):
                    b = f"{npath(op['file'])}.bak.{aplib.now_ts()}"
                    shutil.copy2(npath(op["file"]), b)
                    op["_backup_path"] = b
                aplib.block_remove(op["file"], name)

        elif kind == "archive_dir":
            src = npath(op["src"])
            if not os.path.isdir(src):
                raise FileNotFoundError(f"archive_dir source missing: {src}")
            dest = f"{src.rstrip(os.sep)}.removed.{aplib.now_ts()}.tar.gz"
            tmp = dest + ".tmp"
            archive(src, tmp)
            try:
                with tarfile.open(tmp, "r:gz") as tf:
                    tf.getmembers()
            except Exception as e:
                os.unlink(tmp)
                raise RuntimeError(f"archive integrity check failed: {src}: {e}")
            os.replace(tmp, dest)
            op["_archive_path"] = dest
            print(f"  archive 생성·검증 완료: {dest}")

        elif kind in aplib.NEW_OPS:
            aplib.apply_op(op)

        else:
            raise RuntimeError(f"unknown op: {kind}")

        completed.append(i)
        completed_ops.append(op)
        print(f"  [{i+1}/{len(ops)}] {kind} OK")

except Exception as e:
    print(f"  FAIL at step {len(completed)+1}: {e}", file=sys.stderr)
    plan["_completed"] = completed
    plan["_completed_ops"] = completed_ops
    plan["_failed_at"] = len(completed)
    plan["_error"] = str(e)
    with open(state_file, "w", encoding="utf-8") as f:
        json.dump(plan, f, ensure_ascii=False, indent=2)
    sys.exit(2)

os.unlink(state_file)
print("  All operations completed.")
PYEOF
