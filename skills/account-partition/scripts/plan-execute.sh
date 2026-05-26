#!/usr/bin/env bash
# Plan JSON (stdin)을 실제로 실행. 단계별로 상태 파일에 진행 기록.
# 사용: echo "$plan_json" | PLAN_DIR=... SCRIPTS_DIR=... plan-execute.sh
# 환경변수:
#   PLAN_DIR    상태 파일 위치 (기본: $HOME)
#   SCRIPTS_DIR shell-rc.sh 위치 (기본: 이 스크립트와 같은 디렉토리)
#
# 성공 시 상태 파일 정리. 실패 시 보존 (rollback이 읽음). exit code:
#   0: 성공
#   1: 사용 오류 (잘못된 JSON 등)
#   2: 부분 실행 후 실패 (상태 파일 보존됨)

set -uo pipefail

PLAN_DIR="${PLAN_DIR:-$HOME}"
STATE_FILE="$PLAN_DIR/.account-partition-state.json"

# 이 스크립트 디렉토리 (SCRIPTS_DIR 미지정 시 폴백)
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPTS_DIR:-$_SELF_DIR}"

PLAN_JSON=$(cat)

# JSON 검증
if ! echo "$PLAN_JSON" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  echo "Error: invalid plan JSON" >&2
  exit 1
fi

mkdir -p "$PLAN_DIR"

# 환경변수로 Python에 값 전달 (heredoc 내 $ interpolation 금지)
export PLAN_JSON_ENV="$PLAN_JSON"
export STATE_FILE_ENV="$STATE_FILE"
export SCRIPTS_DIR_ENV="$SCRIPTS_DIR"

python3 <<'PYEOF'
import json, os, sys, subprocess, datetime

plan = json.loads(os.environ['PLAN_JSON_ENV'])
state_file = os.environ['STATE_FILE_ENV']
scripts_dir = os.environ['SCRIPTS_DIR_ENV']
ops = plan.get("operations", [])

# 초기 상태 파일 기록 (시작 시점 — ops 전체 보존)
with open(state_file, "w") as f:
    json.dump(plan, f, ensure_ascii=False, indent=2)

completed = []

def unique_ts():
    return datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + f"-{os.getpid()}"

def shell_rc(args):
    """shell-rc.sh 호출. 실패해도 무시 (fallback 처리됨)."""
    rc_script = os.path.join(scripts_dir, "shell-rc.sh")
    if os.path.isfile(rc_script):
        subprocess.run(["bash", rc_script] + args, check=False)

try:
    for i, op in enumerate(ops):
        kind = op["op"]

        if kind == "create_dir":
            os.makedirs(op["path"], exist_ok=True)
            if "mode" in op:
                os.chmod(op["path"], int(op["mode"], 8))

        elif kind == "remove_dir":
            subprocess.run(["rm", "-rf", op["path"]], check=True)

        elif kind == "create_symlink":
            src = op["src"]
            dst = op["dst"]
            # src 존재 확인
            if not os.path.exists(src):
                raise FileNotFoundError(f"symlink source does not exist: {src}")
            # dst가 이미 있으면 backup 또는 제거
            if os.path.exists(dst) or os.path.islink(dst):
                if op.get("backup_if_exists"):
                    backup = f"{dst}.bak.{unique_ts()}"
                    subprocess.run(["cp", "-Rp", dst, backup], check=True)
                subprocess.run(["rm", "-rf", dst], check=True)
            os.symlink(src, dst)

        elif kind == "remove_symlink":
            if os.path.islink(op["dst"]):
                os.unlink(op["dst"])

        elif kind == "copy":
            subprocess.run(["cp", "-Rp", op["src"], op["dst"]], check=True)

        elif kind == "move":
            subprocess.run(["mv", op["src"], op["dst"]], check=True)

        elif kind == "append_block":
            f_path = op["file"]
            marker = op.get("marker", "")
            # backup
            if op.get("backup") and os.path.exists(f_path):
                backup = f"{f_path}.bak.{unique_ts()}"
                subprocess.run(["cp", "-p", f_path, backup], check=True)
            # 기존 managed 블록 제거 (idempotency)
            if marker.startswith("# account-partition:"):
                name = marker.split(":", 1)[1].strip()
                shell_rc(["remove", f_path, name])
            # 블록 추가
            with open(f_path, "a") as fh:
                fh.write(marker + "\n")
                for line in op.get("lines", []):
                    fh.write(line + "\n")

        elif kind == "quarantine":
            cfg = op.get("config_dir", "")
            q = os.path.join(cfg, ".account-partition-quarantine")
            os.makedirs(q, exist_ok=True)
            name = os.path.basename(op["path"])
            dst = os.path.join(q, f"{name}.{unique_ts()}")
            subprocess.run(["mv", op["path"], dst], check=True)

        elif kind == "auth_logout":
            cfg = op["config_dir"]
            env = {**os.environ, "CLAUDE_CONFIG_DIR": cfg}
            subprocess.run(
                ["claude", "auth", "logout"],
                env=env,
                check=False,
            )

        elif kind == "remove_block":
            marker = op.get("marker", "")
            if marker.startswith("# account-partition:"):
                name = marker.split(":", 1)[1].strip()
                shell_rc_script = os.path.join(scripts_dir, "shell-rc.sh")
                if os.path.isfile(shell_rc_script):
                    subprocess.run(
                        ["bash", shell_rc_script, "remove", op["file"], name],
                        check=False,
                    )
                else:
                    # fallback: marker + 다음 라인 직접 제거
                    f_path = op["file"]
                    if os.path.exists(f_path):
                        with open(f_path) as fh:
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
                        with open(f_path, "w") as fh:
                            fh.writelines(new_lines)

        elif kind == "archive_dir":
            src = op["src"]
            if not os.path.isdir(src):
                raise FileNotFoundError(f"archive_dir source missing: {src}")
            ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + f"-{os.getpid()}"
            dest = f"{src}.removed.{ts}.tar.gz"
            parent = os.path.dirname(src) or "."
            base = os.path.basename(src)
            subprocess.run(["tar", "czf", dest, "-C", parent, base], check=True)
            if op.get("remove_after"):
                subprocess.run(["rm", "-rf", src], check=True)

        else:
            raise RuntimeError(f"unknown op: {kind}")

        completed.append(i)
        print(f"  [{i+1}/{len(ops)}] {kind} OK")

except Exception as e:
    print(f"  FAIL at step {len(completed)+1}: {e}", file=sys.stderr)
    plan["_completed"] = completed
    plan["_failed_at"] = len(completed)
    plan["_error"] = str(e)
    with open(state_file, "w") as f:
        json.dump(plan, f, ensure_ascii=False, indent=2)
    sys.exit(2)

# 성공 → 상태 파일 정리
os.unlink(state_file)
print("  All operations completed.")
PYEOF
