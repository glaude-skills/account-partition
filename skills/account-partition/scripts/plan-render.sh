#!/usr/bin/env bash
# Plan JSON (stdin)을 사람이 읽을 텍스트로 변환.
# 사용: echo "$plan_json" | plan-render.sh

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/platform.sh"

export PLAN_JSON
PLAN_JSON=$(cat)

python3 - <<'PYEOF'
import json, sys, os

raw = os.environ.get("PLAN_JSON", "")
try:
    plan = json.loads(raw)
except Exception as e:
    print(f"Error: invalid plan JSON: {e}", file=sys.stderr)
    sys.exit(1)

md = plan.get("metadata", {})
ops = plan.get("operations", [])

action_label = {
  "add": "계정 추가",
  "edit": "공유 항목 수정",
  "delete": "계정 연동 해제",
  "unlink": "연동 해제",
  "adopt": "기존 정의 가져오기",
}.get(md.get("action", ""), md.get("action", "?"))

alias = md.get("alias_name", "?")
mode_note = " · 토큰만 분리" if md.get("mode") == "token-only" else ""
print(f"다음 작업을 실행합니다 ({action_label} — claude-{alias}{mode_note}):")
print()
if md.get("mode") == "token-only" and md.get("token_dir"):
  print(f"  설정 폴더(공유)  {md.get('config_dir')}")
  print(f"  토큰 폴더(분리)  {md.get('token_dir')}")
  print()
KIND_LABEL = {"posix": "zsh/bash", "powershell": "PowerShell"}

ITEM_LABEL = {
  "plugins":      "플러그인",
  "skills":       "스킬",
  "commands":     "슬래시 명령",
  "agents":       "서브에이전트",
  "CLAUDE.md":    "글로벌 인스트럭션",
  "settings.json":"전역 설정",
}

def label_for_path(p):
  base = p.rstrip("/").rsplit("/", 1)[-1]
  return ITEM_LABEL.get(base, base)

for op in ops:
  kind = op.get("op")
  if kind == "create_dir":
    mode = op.get("mode", "")
    mode_str = f" (mode {mode})" if mode else ""
    print(f"  생성       {op['path']}{mode_str}")
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
  elif kind == "move":
    print(f"  이동       {op['src']} → {op['dst']}")
  elif kind == "append_block":
    backup_note = " (백업 생성)" if op.get("backup") else ""
    print(f"  추가       {op['file']}{backup_note}")
    for line in op.get("lines", []):
      print(f"             {line}")
  elif kind == "quarantine":
    print(f"  격리 보존  {op['path']} (충돌 사본을 quarantine 디렉토리로 이동)")
  elif kind == "auth_logout":
    print(f"  로그아웃   {op['config_dir']} (claude auth logout)")
  elif kind == "remove_block":
    print(f"  제거       {op['file']} 에서 marker '{op['marker']}' 블록 제거")
  elif kind == "archive_dir":
    print(f"  아카이브   {op['src']} → <src>.removed.<ts>.tar.gz")
  elif kind == "write_block":
    print(f"  셸 등록    [{KIND_LABEL.get(op.get('kind'), op.get('kind'))}] {op['file']}" + (" (백업 생성)" if op.get("backup") else ""))
  elif kind == "remove_external":
    print(f"  외부 정의 제거 [{KIND_LABEL.get(op.get('kind'), op.get('kind'))}] {op['file']} 의 claude-{op['name']} (백업 생성)")
  elif kind == "write_file":
    print(f"  래퍼 작성  {op['path']}" + (" (기존 파일 백업)" if op.get("backup_if_exists") else ""))
  elif kind == "remove_file":
    print(f"  파일 제거  {op['path']} (.bak 로 보관)")
  elif kind == "registry_put":
    print(f"  계정 등록  {op['registry']} ← {op['name']}")
  elif kind == "registry_delete":
    print(f"  계정 삭제  {op['registry']} 에서 {op['name']}")
  elif kind == "keychain_delete":
    print(f"  키체인 삭제 {op['service']} (macOS, 없으면 무시)")
  else:
    print(f"  ?          {kind}: {op}")

warnings = md.get("warnings") or []
if warnings:
  print()
  print("주의:")
  for w in warnings:
    print(f"  · {w}")
print()
print("진행할까요? (예 / 아니오 / 명령 출력만)")
PYEOF
