#!/usr/bin/env python3
"""claude-<name> attach 가로채기 (account-partition).

백그라운드 세션 프로세스는 그 세션을 띄운 계정의 토큰을 쓴다. `claude attach` 로 붙거나
멈춘 세션을 깨우면 데몬이 저장해 둔 토큰 폴더(jobs/<id>/state.json 의 providerEnv)가
그대로 쓰이므로, 다른 계정 명령으로 붙어도 토큰이 바뀌지 않는다.

이 헬퍼는 계정 래퍼가 `attach` 를 받았을 때 대신 실행된다(환경변수는 래퍼가 이미 설정).
- 세션을 띄운 토큰 폴더 == 지금 계정 토큰 폴더: 그대로 `claude attach`
- 다르면: 세션을 멈추고 그 세션 폴더에서 `claude --resume <sessionId> <저장된 옵션>` 을
  포그라운드로 연다. `--bg --resume` 은 저장된 토큰 폴더를 다시 쓰므로 쓰지 않는다.

사용: ap_attach.py attach <id|name> [그 밖의 인자]
"""
from __future__ import annotations

import glob
import json
import os
import shutil
import subprocess
import sys

TOKEN_KEY = "CLAUDE_SECURESTORAGE_CONFIG_DIR"
CONFIG_KEY = "CLAUDE_CONFIG_DIR"


def _setup_io() -> None:
    # Git Bash(mintty) 처럼 콘솔이 아닌 출력은 로캘 인코딩(cp949 등)으로 깨진다
    for s in (sys.stdout, sys.stderr):
        try:
            if not s.isatty():
                s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass


def _norm(p: str) -> str:
    p = os.path.normpath(os.path.expanduser(p))
    return os.path.normcase(p)


def config_dir(env: dict) -> str:
    return env.get(CONFIG_KEY) or os.path.join(os.path.expanduser("~"), ".claude")


def token_dir(env: dict, cfg_default: str) -> str:
    """CLI 가 토큰을 두는 폴더: SECURESTORAGE > CONFIG_DIR > 기본 config."""
    return _norm(env.get(TOKEN_KEY) or env.get(CONFIG_KEY) or cfg_default)


def load_jobs(cfg: str) -> list[dict]:
    out = []
    for f in glob.glob(os.path.join(cfg, "jobs", "*", "state.json")):
        try:
            with open(f, encoding="utf-8") as fh:
                d = json.load(fh)
        except (OSError, ValueError):
            continue
        if d.get("daemonShort") and d.get("sessionId"):
            out.append(d)
    return out


def running_shorts(cfg: str) -> set[str]:
    try:
        with open(os.path.join(cfg, "daemon", "roster.json"), encoding="utf-8") as fh:
            return set((json.load(fh).get("workers") or {}).keys())
    except (OSError, ValueError):
        return set()


def find_job(jobs: list[dict], target: str, running: set[str]) -> tuple[dict | None, list[dict]]:
    """claude attach 와 같은 순서: id(앞부분) 다음 이름 일부. (찾은 것, 후보들)."""
    t = target.lower()
    exact = [j for j in jobs if j["daemonShort"].lower() == t or j["sessionId"].lower() == t]
    if len(exact) == 1:
        return exact[0], exact
    cands = [j for j in jobs if j["sessionId"].lower().startswith(t)] or \
            [j for j in jobs if t in (j.get("name") or "").lower()]
    if len(cands) > 1:
        live = [j for j in cands if j["daemonShort"] in running]
        if len(live) == 1:
            return live[0], cands
    return (cands[0] if len(cands) == 1 else None), cands


def main(argv: list[str], env: dict | None = None) -> int:
    _setup_io()
    env = dict(os.environ) if env is None else env
    claude = shutil.which("claude", path=env.get("PATH")) or "claude"
    if len(argv) < 2 or argv[0] != "attach" or argv[1].startswith("-"):
        return subprocess.call([claude, *argv])
    target = argv[1]
    cfg = config_dir(env)
    jobs = load_jobs(cfg)
    running = running_shorts(cfg)
    job, cands = find_job(jobs, target, running)
    if job is None:
        if len(cands) > 1:
            print(f"'{target}' 에 해당하는 세션이 여러 개입니다. id 로 지정하세요:", file=sys.stderr)
            for j in cands:
                print(f"  {j['daemonShort']}  {j.get('name') or ''}", file=sys.stderr)
            return 1
        return subprocess.call([claude, *argv])

    mine = token_dir(env, cfg)
    theirs = token_dir(job.get("providerEnv") or {}, cfg)
    if mine == theirs:
        return subprocess.call([claude, *argv])

    short, sid = job["daemonShort"], job["sessionId"]
    live = short in running
    print(f"세션 {short} 은(는) 다른 계정 토큰으로 떠 있습니다 ({theirs}).")
    print(f"붙으면 그 토큰이 쓰이므로, 멈추고 지금 계정 토큰({mine})으로 --resume 합니다.")
    if live:
        try:
            ans = input("실행 중인 세션을 멈춥니다. 진행 중인 작업은 중단됩니다. 계속할까요? [y/N] ")
        except EOFError:
            ans = ""
        if ans.strip().lower() not in ("y", "yes"):
            print("취소했습니다.")
            return 1
        rc = subprocess.call([claude, "stop", short])
        if rc != 0:
            print(f"claude stop {short} 실패 (종료 코드 {rc}).", file=sys.stderr)
            return rc
    cwd = job.get("cwd") or os.getcwd()
    if not os.path.isdir(cwd):
        print(f"세션 폴더가 없습니다: {cwd}", file=sys.stderr)
        return 1
    flags = [str(f) for f in (job.get("respawnFlags") or [])]
    return subprocess.call([claude, "--resume", sid, *flags, *argv[2:]], cwd=cwd)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
