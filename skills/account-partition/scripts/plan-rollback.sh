#!/usr/bin/env bash
# 부분 진행된 plan을 상태 파일 기반으로 역순 롤백.
# 사용: PLAN_DIR=... [SCRIPTS_DIR=...] plan-rollback.sh
# 환경변수:
#   PLAN_DIR     상태 파일 위치 (필수)
#   SCRIPTS_DIR  (호환용, 사용하지 않음 — aplib.py 는 platform.sh 가 찾는다)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/platform.sh"

PLAN_DIR="${PLAN_DIR:?PLAN_DIR is required}"
STATE_FILE="$PLAN_DIR/.account-partition-state.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "Error: no state file at $STATE_FILE — nothing to rollback" >&2
  exit 1
fi

STATE_FILE_ENV="$STATE_FILE" python3 <<'PYEOF'
import json, os, sys, shutil, glob, tarfile, datetime

sys.path.insert(0, os.path.dirname(os.environ["AP_LIB"]))
import aplib
from aplib import npath

state_file = npath(os.environ["STATE_FILE_ENV"])
with open(state_file, encoding="utf-8") as f:
    plan = json.load(f)

completed = plan.get("_completed", [])
ops = plan.get("operations", [])
_list = plan.get("_completed_ops", [])
meta_map = {completed[idx]: _list[idx] for idx in range(len(_list))} if _list else {}

print(f"  rolling back {len(completed)} completed step(s) in reverse...")

for i in reversed(completed):
    op = ops[i]
    meta = meta_map.get(i, op)
    kind = op["op"]
    try:
        if kind == "create_dir":
            p = npath(op["path"])
            if os.path.isdir(p) and not aplib.is_link(p) and not os.listdir(p):
                os.rmdir(p)
                print(f"  [{i}] rollback create_dir: rmdir {op['path']}")
            else:
                print(f"  [{i}] rollback create_dir: skipped (not empty) {op['path']}")
        elif kind == "create_symlink":
            dst = npath(op["dst"])
            if aplib.is_link(dst):
                aplib.remove_link(dst)
            if meta.get("_backup_link"):
                aplib.make_link(meta["_backup_link"], dst)
                print(f"  [{i}] rollback create_symlink: 기존 링크 복원 {dst} → {meta['_backup_link']}")
            elif meta.get("_backup_path") and os.path.exists(meta["_backup_path"]):
                shutil.move(meta["_backup_path"], dst)
                print(f"  [{i}] rollback create_symlink: 백업 복원 {meta['_backup_path']} → {op['dst']}")
            else:
                print(f"  [{i}] rollback create_symlink: rm {op['dst']}")
        elif kind == "remove_symlink":
            print(f"  [{i}] rollback remove_symlink: 수동 복원 필요 (원래 src 정보 없음)", file=sys.stderr)
        elif kind == "copy":
            if os.path.lexists(npath(op["dst"])):
                aplib.remove_tree(op["dst"])
                print(f"  [{i}] rollback copy: rm {op['dst']}")
        elif kind == "move":
            if os.path.lexists(npath(op["dst"])):
                shutil.move(npath(op["dst"]), npath(op["src"]))
                print(f"  [{i}] rollback move: mv {op['dst']} → {op['src']}")
        elif kind == "append_block":
            marker = op.get("marker", "")
            if marker.startswith("# account-partition:"):
                name = marker.split(":", 1)[1].strip()
                aplib.block_remove(op["file"], name)
                print(f"  [{i}] rollback append_block: removed marker '{name}' from {op['file']}")
        elif kind == "quarantine":
            print(f"  [{i}] rollback quarantine: 자동 복원 미지원, 수동 확인 필요 (quarantine 디렉토리 참조)", file=sys.stderr)
        elif kind == "auth_logout":
            print(f"  [{i}] rollback auth_logout: 자동 복원 불가 — 필요 시 'claude auth login' 수동 실행", file=sys.stderr)
        elif kind == "remove_block":
            b = meta.get("_backup_path")
            if b and os.path.exists(b):
                shutil.copy2(b, npath(op["file"]))
                print(f"  [{i}] rollback remove_block: {b} → {op['file']} 복원")
            else:
                print(f"  [{i}] rollback remove_block: 자동 복원 불가 — 셸 설정 파일 백업에서 수동 복구", file=sys.stderr)
        elif kind == "archive_dir":
            src = npath(op["src"])
            recorded = meta.get("_archive_path")
            archives = [recorded] if recorded and os.path.exists(recorded) else \
                sorted(glob.glob(f"{src}.removed.*.tar.gz"), key=os.path.getmtime, reverse=True)
            if archives:
                if not os.path.exists(src):
                    aplib.extract_archive(archives[0], os.path.dirname(src) or ".")
                print(f"  [{i}] rollback archive_dir: {archives[0]} → {op['src']} 복원")
            else:
                print(f"  [{i}] rollback archive_dir: archive 파일 없음 — 수동 확인 필요", file=sys.stderr)
        elif kind in aplib.NEW_OPS:
            print(f"  [{i}] rollback {kind}: {aplib.rollback_op(meta)}")
        else:
            print(f"  [{i}] unknown op for rollback: {kind}", file=sys.stderr)
    except Exception as e:
        print(f"  [{i}] rollback {kind} FAILED: {e}", file=sys.stderr)

ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + f"-{os.getpid()}"
archive = f"{state_file}.rolled-back.{ts}"
os.rename(state_file, archive)
print(f"  state archived as: {archive}")
PYEOF
