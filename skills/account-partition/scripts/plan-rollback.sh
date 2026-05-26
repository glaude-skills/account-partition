#!/usr/bin/env bash
# 부분 진행된 plan을 상태 파일 기반으로 역순 롤백.
# 사용: PLAN_DIR=... [SCRIPTS_DIR=...] plan-rollback.sh
# 환경변수:
#   PLAN_DIR     상태 파일 위치 (필수)
#   SCRIPTS_DIR  shell-rc.sh 위치 (append_block 롤백에 필요)
set -uo pipefail

PLAN_DIR="${PLAN_DIR:?PLAN_DIR is required}"
STATE_FILE="$PLAN_DIR/.account-partition-state.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "Error: no state file at $STATE_FILE — nothing to rollback" >&2
  exit 1
fi

# 현재 스크립트 위치를 SCRIPTS_DIR 폴백으로 사용
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="${SCRIPTS_DIR:-$SELF_DIR}"

STATE_FILE_ENV="$STATE_FILE" SCRIPTS_DIR_ENV="$SCRIPTS_DIR" python3 <<'PYEOF'
import json, os, sys, subprocess, datetime

state_file = os.environ["STATE_FILE_ENV"]
scripts_dir = os.environ["SCRIPTS_DIR_ENV"]

with open(state_file) as f:
    plan = json.load(f)

completed = plan.get("_completed", [])
ops = plan.get("operations", [])

print(f"  rolling back {len(completed)} completed step(s) in reverse...")

for i in reversed(completed):
    op = ops[i]
    kind = op["op"]
    try:
        if kind == "create_dir":
            # 빈 디렉토리만 제거
            if os.path.isdir(op["path"]) and not os.listdir(op["path"]):
                os.rmdir(op["path"])
                print(f"  [{i}] rollback create_dir: rmdir {op['path']}")
            else:
                print(f"  [{i}] rollback create_dir: skipped (not empty) {op['path']}")
        elif kind == "create_symlink":
            if os.path.islink(op["dst"]):
                os.unlink(op["dst"])
                print(f"  [{i}] rollback create_symlink: rm {op['dst']}")
        elif kind == "remove_symlink":
            # 반대 방향은 정보 부족 — 사용자 안내
            print(f"  [{i}] rollback remove_symlink: 수동 복원 필요 (원래 src 정보 없음)", file=sys.stderr)
        elif kind == "copy":
            if os.path.exists(op["dst"]):
                subprocess.run(["rm", "-rf", op["dst"]], check=False)
                print(f"  [{i}] rollback copy: rm {op['dst']}")
        elif kind == "move":
            # 반대 방향 이동
            if os.path.exists(op["dst"]):
                subprocess.run(["mv", op["dst"], op["src"]], check=False)
                print(f"  [{i}] rollback move: mv {op['dst']} → {op['src']}")
        elif kind == "append_block":
            marker = op.get("marker", "")
            if marker.startswith("# account-partition:"):
                name = marker.split(":", 1)[1].strip()
                shell_rc = os.path.join(scripts_dir, "shell-rc.sh")
                if os.path.isfile(shell_rc):
                    subprocess.run(["bash", shell_rc, "remove", op["file"], name], check=False)
                    print(f"  [{i}] rollback append_block: removed marker '{name}' from {op['file']}")
                else:
                    # fallback: marker + 다음 라인 직접 제거
                    if os.path.exists(op["file"]):
                        with open(op["file"]) as fh:
                            lines = fh.readlines()
                        new_lines = []
                        skip = False
                        for ln in lines:
                            if skip:
                                skip = False
                                continue
                            if ln.strip() == marker:
                                skip = True
                                continue
                            new_lines.append(ln)
                        with open(op["file"], "w") as fh:
                            fh.writelines(new_lines)
                        print(f"  [{i}] rollback append_block (fallback): removed marker from {op['file']}")
        elif kind == "quarantine":
            print(f"  [{i}] rollback quarantine: 자동 복원 미지원, 수동 확인 필요 (quarantine 디렉토리 참조)", file=sys.stderr)
        elif kind == "auth_logout":
            print(f"  [{i}] rollback auth_logout: 자동 복원 불가 — 필요 시 'claude auth login' 수동 실행", file=sys.stderr)
        elif kind == "remove_block":
            print(f"  [{i}] rollback remove_block: 자동 복원 불가 — ~/.zshrc 백업에서 수동 복구", file=sys.stderr)
        elif kind == "archive_dir":
            import glob
            src = op["src"]
            archives = sorted(glob.glob(f"{src}.removed.*.tar.gz"), key=os.path.getmtime, reverse=True)
            if archives:
                latest = archives[0]
                parent = os.path.dirname(src) or "."
                subprocess.run(["tar", "xzf", latest, "-C", parent], check=False)
                print(f"  [{i}] rollback archive_dir: {latest} → {src} 복원")
            else:
                print(f"  [{i}] rollback archive_dir: archive 파일 없음 — 수동 확인 필요", file=sys.stderr)
        else:
            print(f"  [{i}] unknown op for rollback: {kind}", file=sys.stderr)
    except Exception as e:
        print(f"  [{i}] rollback {kind} FAILED: {e}", file=sys.stderr)

# 상태 파일 archive
ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + f"-{os.getpid()}"
archive = f"{state_file}.rolled-back.{ts}"
os.rename(state_file, archive)
print(f"  state archived as: {archive}")
PYEOF
