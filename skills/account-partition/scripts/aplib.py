#!/usr/bin/env python3
"""account-partition 공통 라이브러리 + CLI.

멀티 OS(macOS/Linux/Windows) 경로 처리, 셸 4종(zsh/bash/PowerShell/cmd 래퍼) 블록 렌더링·편집,
외부 정의 파서(adopt), 계정 registry, 새 plan 연산을 담당한다.
설계: docs/work/multi-os-token-partition/design.md

CLI:
  aplib.py os                                   → macos|linux|windows
  aplib.py npath <path>                         → OS 네이티브 경로
  aplib.py targets                              → 감지된 셸 대상 JSON
  aplib.py render <kind> <account-json>         → 블록/래퍼 텍스트 (kind: posix|powershell|cmd|sh)
  aplib.py accounts [--registry R]              → registry + 외부 정의 요약 JSON
  aplib.py plan-add  --name N --mode standard|token-only --config-dir C [--token-dir T]
                     [--shared-pool P] [--shared CSV] [--extra-env K=V,...] [--manual]
  aplib.py plan-adopt --name N --signature S [--registry R]
  aplib.py plan-unlink --name N [--registry R]
  aplib.py env <name> [--registry R]            → 계정 env를 KEY=VALUE 줄로 (빈 값 = unset)
  aplib.py run <name> -- <cmd...>               → 계정 env로 명령 실행
  aplib.py apply-op <op-json>                   → plan 연산 1개 실행, 갱신된 op JSON 출력
  aplib.py rollback-op <op-json>                → plan 연산 1개 롤백
"""
from __future__ import annotations

import datetime
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys

MANAGED_KEYS = ("CLAUDE_CONFIG_DIR", "CLAUDE_SECURESTORAGE_CONFIG_DIR")
DEFAULT_CONFIG = "~/.claude"
NAME_RE = r"[A-Za-z0-9_-]+"

# ─────────────────────────── OS / 경로 ───────────────────────────


def ap_os() -> str:
    o = os.environ.get("AP_OS_OVERRIDE", "").strip()
    if o:
        return o
    if sys.platform.startswith("win") or sys.platform in ("cygwin", "msys"):
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    return "linux"


def _real_windows() -> bool:
    return sys.platform.startswith("win")


def bash_exe() -> str:
    """Python 에서 bash 호출용. Windows 의 'bash' 는 WSL 로 풀리므로 platform.sh 가 준 경로 우선."""
    return os.environ.get("AP_BASH") or shutil.which("bash") or "bash"


def npath(p: str) -> str:
    """bash 쪽에서 넘어온 경로를 이 Python이 쓸 수 있는 네이티브 경로로."""
    if not p:
        return p
    if p.startswith("~"):
        p = os.path.expanduser(p)
    if not _real_windows():
        return p
    m = re.match(r"^/([a-zA-Z])(/.*)?$", p)
    if m:
        return f"{m.group(1).upper()}:{(m.group(2) or '/')}".replace("/", "\\")
    if p.startswith("/"):
        cyg = shutil.which("cygpath")
        if cyg:
            r = subprocess.run([cyg, "-w", p], capture_output=True, text=True)
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout.strip()
    return p


def home() -> str:
    h = os.environ.get("AP_HOME") or os.environ.get("HOME") or os.path.expanduser("~")
    return os.path.normpath(npath(h))


def _norm_cmp(p: str) -> str:
    p = os.path.normpath(npath(p)).replace("\\", "/")
    return p.lower() if _real_windows() else p


def to_home_rel(p: str) -> str:
    """절대/홈 표기 경로를 '~/x' 형태(홈 밖이면 '/'구분 절대경로)로 정규화."""
    if not p:
        return p
    p = p.strip()
    if p.startswith("~"):
        rest = p[1:].lstrip("/\\")
        return "~/" + rest.replace("\\", "/") if rest else "~"
    full = os.path.normpath(npath(p))
    h = home()
    if _norm_cmp(full) == _norm_cmp(h):
        return "~"
    hp = _norm_cmp(h).rstrip("/") + "/"
    if _norm_cmp(full).startswith(hp):
        rest = full[len(h):].lstrip("/\\").replace("\\", "/")
        return "~/" + rest
    return full.replace("\\", "/")


def from_home_rel(p: str) -> str:
    """'~/x' → 이 Python 기준 절대 경로."""
    if p == "~":
        return home()
    if p.startswith("~/"):
        return os.path.normpath(os.path.join(home(), p[2:]))
    return os.path.normpath(npath(p))


def is_default_config(p: str | None) -> bool:
    return (p or DEFAULT_CONFIG) == DEFAULT_CONFIG


def now_ts() -> str:
    return datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + f"-{os.getpid()}"


# ─────────────────────────── 링크 (junction/symlink) ───────────────────────────


def is_link(p: str) -> bool:
    p = npath(p)
    if os.path.islink(p):
        return True
    isj = getattr(os.path, "isjunction", None)
    if isj and isj(p):
        return True
    return False


def make_link(src: str, dst: str) -> str:
    """dst → src 링크. Windows 디렉토리는 junction. 반환: 'symlink'|'junction'."""
    s, d = npath(src), npath(dst)
    if _real_windows() and os.path.isdir(s):
        import _winapi  # type: ignore
        _winapi.CreateJunction(os.path.abspath(s), os.path.abspath(d))
        return "junction"
    try:
        os.symlink(s, d, target_is_directory=os.path.isdir(s))
    except OSError as e:
        if not _real_windows():
            raise
        # 개발자 모드가 꺼진 Windows: 같은 볼륨이면 권한 없이 되는 하드링크로 대체
        try:
            os.link(s, d)
        except OSError as e2:
            raise OSError(
                f"파일 링크 생성 실패 ({d}). Windows 설정 > 개발자용 > 개발자 모드를 켜고 다시 시도하세요: {e} / {e2}"
            ) from e2
        return "hardlink"
    return "symlink"


def remove_link(p: str) -> None:
    """링크만 제거. junction은 rmdir (대상 내용 보존)."""
    n = npath(p)
    isj = getattr(os.path, "isjunction", None)
    if isj and isj(n):
        os.rmdir(n)
    elif os.path.islink(n):
        if _real_windows() and os.path.isdir(n):
            os.rmdir(n)
        else:
            os.unlink(n)


def remove_tree(p: str) -> None:
    """링크면 링크만, 실체면 트리 전체 제거. junction 안으로 따라 들어가지 않는다."""
    n = npath(p)
    if is_link(n):
        remove_link(n)
        return
    if os.path.isdir(n):
        for entry in os.listdir(n):
            remove_tree(os.path.join(n, entry))
        os.rmdir(n)
    elif os.path.lexists(n):
        os.unlink(n)


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if _real_windows():
        r = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/NH", "/FO", "CSV"],
                           capture_output=True, text=True)
        return f'"{pid}"' in r.stdout
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


# ─────────────────────────── 셸 대상 감지 ───────────────────────────


def _ps_profile(exe: str) -> str | None:
    try:
        r = subprocess.run([exe, "-NoProfile", "-NonInteractive", "-Command",
                            "$PROFILE.CurrentUserCurrentHost"],
                           capture_output=True, text=True, timeout=30)
    except Exception:
        return None
    out = r.stdout.strip().splitlines()
    return out[-1].strip() if r.returncode == 0 and out else None


def detect_targets() -> list[dict]:
    override = os.environ.get("AP_TARGETS")
    if override:
        return json.loads(override)
    h = home()
    osname = ap_os()
    targets: list[dict] = []
    zshrc = os.path.join(h, ".zshrc")
    if shutil.which("zsh") or os.path.exists(zshrc):
        targets.append({"kind": "zsh", "path": zshrc})
    if shutil.which("bash"):
        targets.append({"kind": "bash", "path": os.path.join(h, ".bashrc")})
    seen = set()
    for exe in ("powershell", "pwsh"):
        found = shutil.which(exe)
        if not found:
            continue
        prof = _ps_profile(found)
        if prof and _norm_cmp(prof) not in seen:
            seen.add(_norm_cmp(prof))
            targets.append({"kind": "powershell", "path": prof, "edition": exe})
    if osname == "windows":
        targets.append({"kind": "cmd", "path": os.path.join(h, "bin")})
    return targets


def target_warnings(targets: list[dict]) -> list[str]:
    warns = []
    h = home()
    for t in targets:
        if t["kind"] == "cmd":
            bindir = _norm_cmp(t["path"])
            path_dirs = [_norm_cmp(npath(x)) for x in re.split(r"[;:]" if not _real_windows() else ";",
                                                                os.environ.get("PATH", "")) if x]
            if bindir not in path_dirs and not os.environ.get("AP_TARGETS"):
                warns.append(f"{t['path']} 가 PATH에 없습니다. cmd에서 claude-<이름>을 쓰려면 사용자 PATH에 이 폴더를 추가하세요.")
        if t["kind"] == "bash" and ap_os() == "macos":
            bp = os.path.join(h, ".bash_profile")
            if os.path.exists(bp):
                with open(bp, "rb") as f:
                    if b".bashrc" not in f.read():
                        warns.append("~/.bash_profile 이 ~/.bashrc 를 불러오지 않습니다. bash 로그인 셸에서 쓰려면 'source ~/.bashrc' 를 추가하세요.")
    return warns


# ─────────────────────────── 계정 → env ───────────────────────────


def account_env(acct: dict) -> list[tuple[str, str | None]]:
    """[(KEY, home-rel 경로 또는 None=unset)] + extra_env (리터럴)."""
    cfg = acct.get("config_dir") or DEFAULT_CONFIG
    tok = acct.get("token_dir")
    env: list[tuple[str, str | None]] = [
        ("CLAUDE_CONFIG_DIR", None if is_default_config(cfg) else cfg),
        ("CLAUDE_SECURESTORAGE_CONFIG_DIR", tok if tok else None),
    ]
    return env


def resolved_env(acct: dict, osname: str | None = None) -> dict[str, str | None]:
    """실제 프로세스에 넘길 값 (셸들이 만들어내는 문자열과 동일해야 함)."""
    osname = osname or ap_os()
    out: dict[str, str | None] = {}
    for k, v in account_env(acct):
        out[k] = None if v is None else _expand_for_process(v, osname)
    for k, v in (acct.get("extra_env") or {}).items():
        out[k] = v
    return out


def _expand_for_process(p: str, osname: str) -> str:
    if p.startswith("~/") or p == "~":
        rest = p[2:] if p != "~" else ""
        if osname == "windows":
            base = os.environ.get("USERPROFILE") or home()
            return base + ("\\" + rest.replace("/", "\\") if rest else "")
        return home() + ("/" + rest if rest else "")
    return p.replace("/", "\\") if osname == "windows" else p


# ─────────────────────────── 렌더링 ───────────────────────────


def _begin(name: str) -> str:
    return f"# >>> account-partition: {name} >>>"


def _end(name: str) -> str:
    return f"# <<< account-partition: {name} <<<"


def _posix_path(p: str, osname: str) -> str:
    if p.startswith("~/") or p == "~":
        rest = p[2:] if p != "~" else ""
        if osname == "windows":
            return '"$USERPROFILE' + ("\\" + rest.replace("/", "\\") if rest else "") + '"'
        return '"$HOME' + ("/" + rest if rest else "") + '"'
    if osname == "windows":
        return shlex.quote(p.replace("/", "\\"))
    return shlex.quote(p)


def _ps_quote(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def _ps_path(p: str) -> str:
    if p == "~":
        return "$HOME"
    win = ap_os() == "windows"
    if p.startswith("~/"):
        rest = p[2:].replace("/", "\\") if win else p[2:]
        return f"(Join-Path $HOME {_ps_quote(rest)})"
    return _ps_quote(p.replace("/", "\\") if win else p)


def _cmd_path(p: str) -> str:
    if p == "~":
        return "%USERPROFILE%"
    if p.startswith("~/"):
        return "%USERPROFILE%\\" + p[2:].replace("/", "\\")
    return p.replace("/", "\\")


def render_posix(name: str, acct: dict, osname: str | None = None) -> list[str]:
    osname = osname or ap_os()
    parts = ["env", "-u", "CLAUDE_CONFIG_DIR", "-u", "CLAUDE_SECURESTORAGE_CONFIG_DIR"]
    for k, v in account_env(acct):
        if v is not None:
            parts.append(f"{k}={_posix_path(v, osname)}")
    for k, v in (acct.get("extra_env") or {}).items():
        parts.append(f"{k}={shlex.quote(v)}")
    parts += ["claude", '"$@"']
    return [
        _begin(name),
        f"unalias claude-{name} 2>/dev/null || true",
        f"claude-{name}() {{ {' '.join(parts)}; }}",
        _end(name),
    ]


def render_powershell(name: str, acct: dict) -> list[str]:
    extra = acct.get("extra_env") or {}
    keys = list(MANAGED_KEYS) + [k for k in extra if k not in MANAGED_KEYS]
    keys_lit = ", ".join(_ps_quote(k) for k in keys)
    sets = []
    for k, v in account_env(acct):
        val = "$null" if v is None else _ps_path(v)
        sets.append(f"    [Environment]::SetEnvironmentVariable({_ps_quote(k)}, {val}, 'Process')")
    for k, v in extra.items():
        sets.append(f"    [Environment]::SetEnvironmentVariable({_ps_quote(k)}, {_ps_quote(v)}, 'Process')")
    return [
        _begin(name),
        f"function claude-{name} {{",
        f"  $apKeys = @({keys_lit})",
        "  $apSaved = @{}",
        "  foreach ($k in $apKeys) { $apSaved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process') }",
        "  try {",
        *sets,
        "    $apExe = Get-Command claude -CommandType Application -ErrorAction Stop | Select-Object -First 1",
        "    & $apExe @args",
        "  } finally {",
        "    foreach ($k in $apKeys) { [Environment]::SetEnvironmentVariable($k, $apSaved[$k], 'Process') }",
        "  }",
        "}",
        _end(name),
    ]


def render_cmd(name: str, acct: dict) -> list[str]:
    lines = ["@echo off", f"rem >>> account-partition: {name} (managed - do not edit) >>>", "setlocal"]
    for k, v in account_env(acct):
        lines.append(f'set "{k}={"" if v is None else _cmd_path(v)}"')
    for k, v in (acct.get("extra_env") or {}).items():
        lines.append(f'set "{k}={v}"')
    lines.append("claude %*")
    return lines


def render_sh(name: str, acct: dict, osname: str | None = None) -> list[str]:
    osname = osname or ap_os()
    lines = ["#!/usr/bin/env bash", f"# >>> account-partition: {name} (managed - do not edit) >>>",
             "unset CLAUDE_CONFIG_DIR CLAUDE_SECURESTORAGE_CONFIG_DIR"]
    for k, v in account_env(acct):
        if v is not None:
            lines.append(f"export {k}={_posix_path(v, osname)}")
    for k, v in (acct.get("extra_env") or {}).items():
        lines.append(f"export {k}={shlex.quote(v)}")
    lines.append('exec claude "$@"')
    return lines


def render(kind: str, name: str, acct: dict) -> list[str]:
    if kind in ("posix", "zsh", "bash"):
        return render_posix(name, acct)
    if kind == "powershell":
        return render_powershell(name, acct)
    if kind == "cmd":
        return render_cmd(name, acct)
    if kind == "sh":
        return render_sh(name, acct)
    raise ValueError(f"unknown kind: {kind}")


# ─────────────────────────── 바이트 수준 파일 편집 ───────────────────────────


def _read_bytes(path: str) -> bytes:
    p = npath(path)
    if not os.path.exists(p):
        return b""
    with open(p, "rb") as f:
        return f.read()


def _write_bytes(path: str, data: bytes) -> None:
    p = npath(path)
    d = os.path.dirname(p)
    if d:
        os.makedirs(d, exist_ok=True)
    tmp = p + f".ap-tmp-{os.getpid()}"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, p)


def _split(data: bytes) -> tuple[bytes, list[bytes], bytes]:
    """(bom, lines-without-eol, eol)"""
    bom = b""
    if data.startswith(b"\xef\xbb\xbf"):
        bom, data = b"\xef\xbb\xbf", data[3:]
    eol = b"\r\n" if b"\r\n" in data else b"\n"
    lines = data.split(b"\n")
    lines = [ln[:-1] if ln.endswith(b"\r") else ln for ln in lines]
    if lines and lines[-1] == b"":
        lines.pop()
    return bom, lines, eol


def _join(bom: bytes, lines: list[bytes], eol: bytes) -> bytes:
    if not lines:
        return bom
    return bom + eol.join(lines) + eol


def _managed_ranges(lines: list[bytes], name: str) -> list[tuple[int, int]]:
    """관리 블록 [start, end] (포함) 목록. 새 형식 + v0.4 형식."""
    n = re.escape(name.encode())
    begin = re.compile(rb"^# >>> account-partition: " + n + rb" >>>\s*$")
    end = re.compile(rb"^# <<< account-partition: " + n + rb" <<<\s*$")
    legacy = re.compile(rb"^# account-partition:\s*" + n + rb"\s*$")
    legacy_alias = re.compile(rb"^\s*alias\s+claude-" + n + rb"\s*=")
    out = []
    i = 0
    while i < len(lines):
        if begin.match(lines[i]):
            j = i + 1
            while j < len(lines) and not end.match(lines[j]):
                j += 1
            if j >= len(lines):
                raise RuntimeError(f"account-partition: '{name}' 블록의 끝 마커가 없습니다. 파일을 직접 확인하세요.")
            out.append((i, j))
            i = j + 1
            continue
        if legacy.match(lines[i]):
            if i + 1 < len(lines) and legacy_alias.match(lines[i + 1]):
                out.append((i, i + 1))
                i += 2
            else:
                out.append((i, i))
                i += 1
            continue
        i += 1
    return out


def block_remove(path: str, name: str) -> bool:
    data = _read_bytes(path)
    if not data:
        return False
    bom, lines, eol = _split(data)
    ranges = _managed_ranges(lines, name)
    if not ranges:
        return False
    drop = set()
    for s, e in ranges:
        drop.update(range(s, e + 1))
    new = [ln for i, ln in enumerate(lines) if i not in drop]
    _write_bytes(path, _join(bom, new, eol))
    return True


def block_write(path: str, name: str, block: list[str], new_file_bom: bool = False,
                new_file_eol: bytes | None = None) -> None:
    """기존 관리 블록을 같은 자리에서 교체, 없으면 파일 끝에 추가."""
    data = _read_bytes(path)
    if data:
        bom, lines, eol = _split(data)
    else:
        bom = b"\xef\xbb\xbf" if new_file_bom else b""
        lines, eol = [], (new_file_eol or b"\n")
    enc = [ln.encode("ascii") for ln in block]
    ranges = _managed_ranges(lines, name)
    if ranges:
        s0, e0 = ranges[0]
        drop = set()
        for s, e in ranges:
            drop.update(range(s, e + 1))
        new = []
        for i, ln in enumerate(lines):
            if i == s0:
                new.extend(enc)
            if i not in drop:
                new.append(ln)
        lines = new
    else:
        if lines and lines[-1].strip() != b"":
            lines.append(b"")
        lines.extend(enc)
    _write_bytes(path, _join(bom, lines, eol))


def list_blocks(path: str) -> list[str]:
    data = _read_bytes(path)
    if not data:
        return []
    _, lines, _ = _split(data)
    names = []
    for ln in lines:
        m = re.match(rb"^# >>> account-partition: (" + NAME_RE.encode() + rb") >>>", ln)
        if m:
            names.append(m.group(1).decode())
    for i, ln in enumerate(lines):
        m = re.match(rb"^# account-partition:\s*(" + NAME_RE.encode() + rb")\s*$", ln)
        if m and i + 1 < len(lines) and re.match(rb"^\s*alias\s+claude-" + re.escape(m.group(1)) + rb"\s*=",
                                                 lines[i + 1]):
            names.append(m.group(1).decode())
    return sorted(set(names))


# ─────────────────────────── 외부 정의 파서 (adopt) ───────────────────────────

_HOME_PATTERNS = [
    r"^\$\{HOME\}", r"^\$HOME", r"^~", r"^\$\{USERPROFILE\}", r"^\$USERPROFILE",
    r"^%USERPROFILE%", r"^\$env:USERPROFILE", r"^\$env:HOME", r"^\$HOME",
]


def _norm_value_path(v: str) -> str:
    v = v.strip()
    m = re.match(r"""^\(?\s*Join-Path\s+\$(?:HOME|env:USERPROFILE|env:HOME)\s+['"]([^'"]*)['"]\s*\)?$""", v,
                 flags=re.IGNORECASE)
    if m:
        rest = m.group(1).lstrip("/\\")
        return "~/" + rest.replace("\\", "/") if rest else "~"
    v = v.strip('"').strip("'")
    for pat in _HOME_PATTERNS:
        m = re.match(pat, v, flags=re.IGNORECASE)
        if m:
            rest = v[m.end():].lstrip("/\\")
            return "~/" + rest.replace("\\", "/") if rest else "~"
    return to_home_rel(v)


def _strip_comment_ps(line: str) -> str:
    return line.split("#", 1)[0] if line.lstrip().startswith("#") else line


class Unparseable(Exception):
    pass


def _parse_posix_tokens(tokens: list[str]) -> dict:
    """[env [-u X]...] VAR=v ... [command|exec] claude "$@" → 정의."""
    sets: dict[str, str] = {}
    unsets: set[str] = set()
    i = 0
    if tokens and tokens[0] == "env":
        i = 1
        while i < len(tokens) and tokens[i] == "-u":
            unsets.add(tokens[i + 1])
            i += 2
    while i < len(tokens) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[i]):
        k, v = tokens[i].split("=", 1)
        sets[k] = v
        i += 1
    while i < len(tokens) and tokens[i] in ("command", "exec"):
        i += 1
    if i >= len(tokens) or tokens[i] != "claude":
        raise Unparseable("claude 호출을 찾을 수 없음")
    rest = tokens[i + 1:]
    if rest not in ([], ['"$@"'], ["$@"], ["@args"], ["%*"]):
        raise Unparseable(f"claude 뒤 인자 해석 불가: {rest}")
    return {"set": sets, "unset": unsets}


def _shlex(s: str) -> list[str]:
    lex = shlex.shlex(s, posix=False, punctuation_chars=False)
    lex.whitespace_split = True
    return [t for t in lex]


def _unquote(v: str) -> str:
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v


def _def_from(sets: dict, unsets: set) -> dict:
    cfg = sets.get("CLAUDE_CONFIG_DIR")
    tok = sets.get("CLAUDE_SECURESTORAGE_CONFIG_DIR")
    cfg_rel = _norm_value_path(_unquote(cfg)) if cfg else DEFAULT_CONFIG
    tok_rel = _norm_value_path(_unquote(tok)) if tok else None
    if tok_rel == cfg_rel:
        tok_rel = None
    extra = {k: _unquote(v) for k, v in sets.items() if k not in MANAGED_KEYS}
    return {"config_dir": cfg_rel, "token_dir": tok_rel, "extra_env": dict(sorted(extra.items()))}


def signature(d: dict) -> str:
    return json.dumps([d.get("config_dir"), d.get("token_dir"), d.get("extra_env") or {}],
                      sort_keys=True, ensure_ascii=True)


def _decode(b: bytes) -> str:
    for enc in ("utf-8", "cp949", "latin-1"):
        try:
            return b.decode(enc)
        except UnicodeDecodeError:
            continue
    return b.decode("utf-8", "replace")


def parse_rc_externals(path: str, kind: str) -> list[dict]:
    """rc/프로필 안의 관리 블록 밖 claude-* 정의. kind: posix|powershell."""
    data = _read_bytes(path)
    if not data:
        return []
    _, blines, _ = _split(data)
    lines = [_decode(b) for b in blines]
    managed = set()
    for nm in list_blocks(path):
        for s, e in _managed_ranges(blines, nm):
            managed.update(range(s, e + 1))
    out = []
    i = 0
    while i < len(lines):
        if i in managed:
            i += 1
            continue
        ln = lines[i]
        if kind == "posix":
            m = re.match(r"^\s*alias\s+claude-(" + NAME_RE + r")=(.*)$", ln)
            if m:
                name, body = m.group(1), _unquote(m.group(2).strip())
                out.append(_mk_ext(path, kind, name, i, i, lambda: _parse_posix_tokens(_shlex(body))))
                i += 1
                continue
            m = re.match(r"^\s*(?:function\s+)?claude-(" + NAME_RE + r")\s*(?:\(\))?\s*\{(.*)$", ln)
            if m:
                name = m.group(1)
                start = i
                body_parts = [m.group(2)]
                j = i
                if "}" not in m.group(2):
                    j = i + 1
                    while j < len(lines) and not re.match(r"^\s*\}\s*$", lines[j]):
                        body_parts.append(lines[j])
                        j += 1
                out.append(_mk_ext(path, kind, name, start, j, lambda bp=body_parts: _parse_posix_body(bp)))
                i = j + 1
                continue
        elif kind == "powershell":
            m = re.match(r"^\s*function\s+claude-(" + NAME_RE + r")\s*\{(.*)$", ln, flags=re.IGNORECASE)
            if m:
                name = m.group(1)
                start = i
                body_parts = [m.group(2)]
                j = i
                if "}" not in m.group(2):
                    j = i + 1
                    while j < len(lines) and not re.match(r"^\}\s*$", lines[j]):
                        body_parts.append(lines[j])
                        j += 1
                out.append(_mk_ext(path, kind, name, start, j, lambda bp=body_parts: _parse_ps_body(bp)))
                i = j + 1
                continue
        i += 1
    # 바로 위에 붙은 주석 줄을 범위에 포함 (제거 시 같이 정리)
    for e in out:
        s = e["start"]
        while s - 1 >= 0 and (s - 1) not in managed and lines[s - 1].lstrip().startswith("#") \
                and lines[s - 1].strip() != "" and not any(o["end"] == s - 1 for o in out):
            s -= 1
        e["comment_start"] = s
    return out


def _mk_ext(path, kind, name, start, end, fn) -> dict:
    e = {"file": path, "kind": kind, "name": name, "start": start, "end": end}
    try:
        p = fn()
        e["definition"] = _def_from(p["set"], p["unset"])
        e["parseable"] = True
    except Unparseable as ex:
        e["parseable"] = False
        e["reason"] = str(ex)
    return e


def _parse_posix_body(parts: list[str]) -> dict:
    sets: dict[str, str] = {}
    unsets: set[str] = set()
    called = False
    for raw in parts:
        for stmt in re.split(r";", raw):
            s = stmt.strip()
            if not s or s.startswith("#") or s == "}":
                continue
            s = s.rstrip("}").strip()
            if not s:
                continue
            m = re.match(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$", s)
            if m:
                sets[m.group(1)] = m.group(2).strip()
                continue
            m = re.match(r"^unset\s+(.+)$", s)
            if m:
                unsets.update(m.group(1).split())
                continue
            p = _parse_posix_tokens(_shlex(s))
            sets.update(p["set"])
            unsets |= p["unset"]
            called = True
    if not called:
        raise Unparseable("claude 호출 없음")
    return {"set": sets, "unset": unsets}


def _parse_ps_body(parts: list[str]) -> dict:
    sets: dict[str, str] = {}
    unsets: set[str] = set()
    called = False
    for raw in parts:
        for stmt in raw.split(";"):
            s = stmt.strip()
            if not s or s.startswith("#") or s == "}":
                continue
            s = s.rstrip("}").strip()
            if not s:
                continue
            m = re.match(r"^\$env:([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$", s, flags=re.IGNORECASE)
            if m:
                sets[m.group(1)] = m.group(2).strip()
                unsets.discard(m.group(1))
                continue
            m = re.match(r"^Remove-Item\s+(?:-Path\s+)?Env:([A-Za-z_][A-Za-z0-9_]*)\b", s, flags=re.IGNORECASE)
            if m:
                unsets.add(m.group(1))
                sets.pop(m.group(1), None)
                continue
            if re.match(r"^&?\s*claude(\.exe|\.cmd)?\s+@args\s*$", s, flags=re.IGNORECASE) or \
                    re.match(r"^&?\s*claude(\.exe|\.cmd)?\s*$", s, flags=re.IGNORECASE):
                called = True
                continue
            raise Unparseable(f"해석 불가 문장: {s}")
    if not called:
        raise Unparseable("claude 호출 없음")
    return {"set": sets, "unset": unsets}


def parse_wrapper(path: str, kind: str) -> dict:
    """~/bin 래퍼 파일(cmd 또는 sh) 해석."""
    name = re.sub(r"\.cmd$", "", os.path.basename(path), flags=re.IGNORECASE)[len("claude-"):]
    e = {"file": path, "kind": kind, "name": name}
    data = _read_bytes(path)
    text = _decode(data)
    if "account-partition:" in text and "(managed" in text:
        e["managed"] = True
    sets: dict[str, str] = {}
    unsets: set[str] = set()
    called = False
    try:
        for raw in text.splitlines():
            s = raw.strip()
            if not s:
                continue
            if kind == "cmd":
                if re.match(r"^@?echo\s+off$", s, re.I) or re.match(r"^(rem\b|::)", s, re.I) or \
                        re.match(r"^setlocal\b", s, re.I):
                    continue
                m = re.match(r'^set\s+"?([A-Za-z_][A-Za-z0-9_]*)=(.*?)"?$', s, re.I)
                if m:
                    if m.group(2) == "":
                        unsets.add(m.group(1))
                        sets.pop(m.group(1), None)
                    else:
                        sets[m.group(1)] = m.group(2)
                    continue
                if re.match(r"^(call\s+)?claude(\.exe|\.cmd)?\s+%\*$", s, re.I):
                    called = True
                    continue
                raise Unparseable(f"해석 불가 문장: {s}")
            else:
                if s.startswith("#"):
                    continue
                m = re.match(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$", s)
                if m:
                    sets[m.group(1)] = m.group(2)
                    continue
                m = re.match(r"^unset\s+(.+)$", s)
                if m:
                    unsets.update(m.group(1).split())
                    continue
                p = _parse_posix_tokens(_shlex(s))
                sets.update(p["set"])
                called = True
        if not called:
            raise Unparseable("claude 호출 없음")
        e["definition"] = _def_from(sets, unsets)
        e["parseable"] = True
    except Unparseable as ex:
        e["parseable"] = False
        e["reason"] = str(ex)
    return e


def scan_externals(targets: list[dict] | None = None) -> list[dict]:
    targets = targets if targets is not None else detect_targets()
    out: list[dict] = []
    for t in targets:
        if t["kind"] in ("zsh", "bash"):
            out += parse_rc_externals(t["path"], "posix")
        elif t["kind"] == "powershell":
            out += parse_rc_externals(t["path"], "powershell")
        elif t["kind"] == "cmd":
            bindir = npath(t["path"])
            if os.path.isdir(bindir):
                for fn in sorted(os.listdir(bindir)):
                    m = re.match(r"^claude-(" + NAME_RE + r")(\.cmd)?$", fn, re.I)
                    if not m:
                        continue
                    w = parse_wrapper(os.path.join(bindir, fn), "cmd" if m.group(2) else "sh")
                    if not w.get("managed"):
                        out.append(w)
    return out


# ─────────────────────────── registry ───────────────────────────


def registry_path(arg: str | None = None) -> str:
    if arg:
        return npath(arg)
    pool = os.environ.get("SHARED_POOL") or os.path.join(home(), ".claude-shared")
    return os.path.join(npath(pool), "accounts.json")


def registry_load(path: str) -> dict:
    p = npath(path)
    if not os.path.exists(p):
        return {"version": 1, "accounts": {}}
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def registry_save(path: str, reg: dict) -> None:
    _write_bytes(path, (json.dumps(reg, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))


# ─────────────────────────── plan 생성 ───────────────────────────


def _write_ops_for(name: str, acct: dict, targets: list[dict]) -> list[dict]:
    ops = []
    for t in targets:
        if t["kind"] in ("zsh", "bash"):
            ops.append({"op": "write_block", "file": t["path"], "kind": "posix", "name": name,
                        "lines": render_posix(name, acct), "backup": True})
        elif t["kind"] == "powershell":
            ops.append({"op": "write_block", "file": t["path"], "kind": "powershell", "name": name,
                        "lines": render_powershell(name, acct), "backup": True,
                        "new_file_bom": True, "new_file_eol": "crlf"})
        elif t["kind"] == "cmd":
            ops.append({"op": "write_file", "path": os.path.join(t["path"], f"claude-{name}.cmd"),
                        "lines": render_cmd(name, acct), "eol": "crlf", "backup_if_exists": True})
            ops.append({"op": "write_file", "path": os.path.join(t["path"], f"claude-{name}"),
                        "lines": render_sh(name, acct), "eol": "lf", "backup_if_exists": True,
                        "executable": True})
    return ops


def _registry_entry(name: str, acct: dict, targets: list[dict]) -> dict:
    return {
        "mode": acct.get("mode", "standard"),
        "config_dir": acct.get("config_dir") or DEFAULT_CONFIG,
        "token_dir": acct.get("token_dir"),
        "extra_env": acct.get("extra_env") or {},
        "shared": acct.get("shared") or [],
        "targets": targets,
        "updated_at": datetime.datetime.now().isoformat(timespec="seconds"),
    }


def plan_add(name: str, mode: str, config_dir: str, token_dir: str | None, shared_pool: str | None,
             shared: list[str], extra_env: dict, manual: bool, registry: str | None) -> dict:
    if not re.fullmatch(NAME_RE, name):
        raise SystemExit(f"invalid name: {name}")
    cfg_rel = to_home_rel(config_dir)
    targets = [] if manual else detect_targets()
    ops: list[dict] = []
    acct: dict = {"mode": mode, "extra_env": extra_env, "shared": shared}
    preconditions = []
    if mode == "token-only":
        tok_rel = to_home_rel(token_dir or f"~/.claude-{name}")
        if tok_rel == cfg_rel:
            raise SystemExit("token-only 모드에서 토큰 폴더는 기준 config 폴더와 달라야 합니다.")
        acct.update({"config_dir": cfg_rel, "token_dir": tok_rel})
        ops.append({"op": "create_dir", "path": from_home_rel(tok_rel), "mode": "0700"})
        preconditions.append({"check": "dir_absent", "path": from_home_rel(tok_rel)})
    else:
        acct.update({"config_dir": cfg_rel, "token_dir": None})
        cfg_abs = from_home_rel(cfg_rel)
        ops.append({"op": "create_dir", "path": cfg_abs, "mode": "0700"})
        preconditions += [{"check": "no_active_session", "config_dir": cfg_abs},
                          {"check": "dir_absent", "path": cfg_abs}]
        shared = [s for s in shared if s != "settings.json"]
        if shared:
            pool = npath(shared_pool or os.path.join(home(), ".claude-shared"))
            ops.append({"op": "create_dir", "path": pool, "mode": "0755"})
            for item in shared:
                src = os.path.join(pool, item)
                if item in ("plugins", "skills", "commands", "agents"):
                    ops.append({"op": "create_dir", "path": src, "mode": "0755"})
                ops.append({"op": "create_symlink", "src": src, "dst": os.path.join(cfg_abs, item),
                            "backup_if_exists": True})
    ops += _write_ops_for(name, acct, targets)
    ops.append({"op": "registry_put", "registry": registry_path(registry), "name": name,
                "entry": _registry_entry(name, acct, targets)})
    return {
        "metadata": {"action": "add", "alias_name": name, "mode": mode,
                     "config_dir": from_home_rel(acct["config_dir"]),
                     "token_dir": from_home_rel(acct["token_dir"]) if acct.get("token_dir") else None,
                     "shell_mode": "manual" if manual else "auto",
                     "manual_lines": {k: render(k, name, acct) for k in ("posix", "powershell", "cmd")}
                     if manual else None,
                     "warnings": target_warnings(targets) + (TOKEN_ONLY_WARNINGS if mode == "token-only" else [])},
        "preconditions": preconditions,
        "operations": ops,
    }


TOKEN_ONLY_WARNINGS = [
    "세션 목록(←← / /resume)에서 다른 계정이 띄운 세션에 참여하면 그 세션을 띄운 계정의 토큰이 쓰입니다. "
    "계정을 바꾸려면 세션을 끝내고 claude-<이름> --resume <id> 로 다시 띄우세요.",
    "기준 계정과 설정·권한·MCP·메모리·플러그인·세션 기록을 모두 공유합니다.",
    "화면에 표시되는 계정 이메일(.claude.json)은 공유되므로 마지막에 로그인한 계정 것으로 보일 수 있습니다. 실제 토큰은 분리돼 있습니다.",
]


def plan_adopt(name: str, sig: str | None, registry: str | None, from_kind: str | None = None) -> dict:
    targets = detect_targets()
    exts = [e for e in scan_externals(targets) if e["name"] == name]
    if not exts:
        raise SystemExit(f"외부 정의 claude-{name} 을(를) 찾지 못했습니다.")
    bad = [e for e in exts if not e.get("parseable")]
    if bad:
        raise SystemExit("해석 불가 정의가 있어 자동 가져오기를 중단합니다: " +
                         "; ".join(f"{e['file']}: {e.get('reason')}" for e in bad))
    sigs = {signature(e["definition"]): e["definition"] for e in exts}
    if sig is None and from_kind:
        picked = [e for e in exts if e["kind"] == from_kind]
        if not picked:
            raise SystemExit(f"{from_kind} 쪽 정의가 없습니다.")
        sig = signature(picked[0]["definition"])
    if sig is None:
        if len(sigs) > 1:
            raise SystemExit("셸마다 정의가 다릅니다. --signature 로 하나를 고르세요.")
        sig = next(iter(sigs))
    if sig not in sigs:
        raise SystemExit("주어진 signature 와 일치하는 정의가 없습니다.")
    d = sigs[sig]
    acct = {"mode": "token-only" if d["token_dir"] else "standard", **d}
    ops: list[dict] = []
    for e in exts:
        if e["kind"] in ("posix", "powershell"):
            ops.append({"op": "remove_external", "file": e["file"], "kind": e["kind"], "name": name,
                        "backup": True})
    write_ops = _write_ops_for(name, acct, targets)
    written_wrappers = {_norm_cmp(o["path"]) for o in write_ops if o["op"] == "write_file"}
    for e in exts:
        if e["kind"] in ("cmd", "sh") and _norm_cmp(e["file"]) not in written_wrappers:
            ops.append({"op": "remove_file", "path": e["file"]})
    ops += write_ops
    ops.append({"op": "registry_put", "registry": registry_path(registry), "name": name,
                "entry": _registry_entry(name, acct, targets)})
    return {
        "metadata": {"action": "adopt", "alias_name": name, "mode": acct["mode"],
                     "config_dir": from_home_rel(acct["config_dir"]),
                     "token_dir": from_home_rel(acct["token_dir"]) if acct.get("token_dir") else None,
                     "definition": d,
                     "warnings": target_warnings(targets) + (TOKEN_ONLY_WARNINGS if acct["mode"] == "token-only" else [])},
        "preconditions": [],
        "operations": ops,
    }


def keychain_service(token_dir_abs: str) -> str:
    h = hashlib.sha256(token_dir_abs.encode("utf-8")).hexdigest()[:8]
    return f"Claude Code-credentials-{h}"


def plan_unlink(name: str, registry: str | None) -> dict:
    reg = registry_load(registry_path(registry))
    acct = reg["accounts"].get(name)
    if not acct:
        raise SystemExit(f"registry 에 '{name}' 이(가) 없습니다. 먼저 adopt 하거나 기존 unlink 흐름을 쓰세요.")
    dependents = sorted(n for n, a in reg["accounts"].items()
                        if n != name and a.get("mode") == "token-only"
                        and (a.get("config_dir") or DEFAULT_CONFIG) == (acct.get("config_dir") or DEFAULT_CONFIG))
    if acct["mode"] != "token-only" and dependents:
        raise SystemExit(
            f"claude-{name} 의 설정 폴더({acct.get('config_dir')})를 토큰만 분리 계정 "
            f"{', '.join('claude-' + d for d in dependents)} 이(가) 공유 중입니다. 먼저 그 계정들을 unlink 하세요.")
    targets = acct.get("targets") or []
    ops: list[dict] = []
    if acct["mode"] != "token-only" and is_default_config(acct.get("config_dir")):
        pass  # 기본 계정(~/.claude)은 로그아웃·폴더 정리 없이 셸 정의만 제거 (기본 계정 보호)
    elif acct["mode"] == "token-only":
        tok = from_home_rel(acct["token_dir"])
        if ap_os() == "macos":
            env_val = resolved_env(acct, "macos")["CLAUDE_SECURESTORAGE_CONFIG_DIR"] or tok
            ops.append({"op": "keychain_delete", "service": keychain_service(env_val)})
        if os.path.isdir(tok):
            ops.append({"op": "archive_dir", "src": tok})
            ops.append({"op": "remove_dir", "path": tok})
    else:
        cfg = from_home_rel(acct["config_dir"])
        ops.append({"op": "auth_logout", "config_dir": cfg})
        if os.path.isdir(cfg) and not is_default_config(acct["config_dir"]):
            ops.append({"op": "archive_dir", "src": cfg})
            ops.append({"op": "remove_dir", "path": cfg})
    for t in targets:
        if t["kind"] in ("zsh", "bash", "powershell"):
            ops.append({"op": "remove_block", "file": t["path"], "name": name,
                        "marker": f"# account-partition: {name}", "backup": True})
        elif t["kind"] == "cmd":
            for fn in (f"claude-{name}.cmd", f"claude-{name}"):
                ops.append({"op": "remove_file", "path": os.path.join(t["path"], fn)})
    ops.append({"op": "registry_delete", "registry": registry_path(registry), "name": name})
    pre = []
    if acct["mode"] != "token-only" and not is_default_config(acct.get("config_dir")):
        pre.append({"check": "no_active_session", "config_dir": from_home_rel(acct["config_dir"])})
    return {"metadata": {"action": "unlink", "alias_name": name, "mode": acct["mode"],
                         "config_dir": from_home_rel(acct["config_dir"])},
            "preconditions": pre, "operations": ops}


# ─────────────────────────── plan 연산 (실행/롤백) ───────────────────────────


def _backup(path: str) -> str | None:
    p = npath(path)
    if not os.path.lexists(p):
        return None
    b = f"{p}.bak.{now_ts()}"
    shutil.copy2(p, b)
    return b


def apply_op(op: dict) -> dict:
    kind = op["op"]
    if kind == "write_block":
        op["_backup_path"] = _backup(op["file"]) if op.get("backup") else None
        op["_created"] = not os.path.exists(npath(op["file"]))
        eol = b"\r\n" if op.get("new_file_eol") == "crlf" else b"\n"
        block_write(op["file"], op["name"], op["lines"], op.get("new_file_bom", False), eol)
    elif kind == "remove_block":
        if os.path.exists(npath(op["file"])):
            op["_backup_path"] = _backup(op["file"]) if op.get("backup", True) else None
            block_remove(op["file"], op["name"])
    elif kind == "remove_external":
        op["_backup_path"] = _backup(op["file"])
        exts = [e for e in parse_rc_externals(op["file"], op["kind"]) if e["name"] == op["name"]]
        data = _read_bytes(op["file"])
        bom, lines, eol = _split(data)
        drop = set()
        for e in exts:
            drop.update(range(e.get("comment_start", e["start"]), e["end"] + 1))
        new = [ln for i, ln in enumerate(lines) if i not in drop]
        while new and new[-1].strip() == b"":
            new.pop()
        _write_bytes(op["file"], _join(bom, new, eol))
    elif kind == "write_file":
        p = npath(op["path"])
        op["_backup_path"] = _backup(p) if op.get("backup_if_exists") else None
        op["_created"] = not os.path.lexists(p)
        eol = b"\r\n" if op.get("eol") == "crlf" else b"\n"
        _write_bytes(p, _join(b"", [ln.encode("ascii") for ln in op["lines"]], eol))
        if op.get("executable") and not _real_windows():
            os.chmod(p, 0o755)
    elif kind == "remove_file":
        p = npath(op["path"])
        if os.path.lexists(p):
            b = f"{p}.bak.{now_ts()}"
            os.replace(p, b)
            op["_backup_path"] = b
    elif kind == "registry_put":
        reg = registry_load(op["registry"])
        op["_previous"] = reg["accounts"].get(op["name"])
        reg["accounts"][op["name"]] = op["entry"]
        registry_save(op["registry"], reg)
    elif kind == "registry_delete":
        reg = registry_load(op["registry"])
        op["_previous"] = reg["accounts"].pop(op["name"], None)
        registry_save(op["registry"], reg)
    elif kind == "keychain_delete":
        r = subprocess.run(["security", "delete-generic-password", "-s", op["service"]],
                           capture_output=True, text=True)
        op["_result"] = "deleted" if r.returncode == 0 else "not-found"
    else:
        raise RuntimeError(f"unknown op: {kind}")
    return op


def rollback_op(op: dict) -> str:
    kind = op["op"]
    if kind in ("write_block", "remove_block", "remove_external", "write_file"):
        target = op.get("file") or op.get("path")
        b = op.get("_backup_path")
        if b and os.path.exists(b):
            shutil.copy2(b, npath(target))
            return f"restored {target} from {b}"
        if op.get("_created") and os.path.exists(npath(target)):
            os.unlink(npath(target))
            return f"removed created {target}"
        if kind == "write_block":
            block_remove(target, op["name"])
            return f"removed block {op['name']} from {target}"
        return f"nothing to restore for {target}"
    if kind == "remove_file":
        b = op.get("_backup_path")
        if b and os.path.exists(b):
            os.replace(b, npath(op["path"]))
            return f"restored {op['path']}"
        return "nothing to restore"
    if kind in ("registry_put", "registry_delete"):
        reg = registry_load(op["registry"])
        prev = op.get("_previous")
        if prev is None:
            reg["accounts"].pop(op["name"], None)
        else:
            reg["accounts"][op["name"]] = prev
        registry_save(op["registry"], reg)
        return f"registry {op['name']} restored"
    if kind == "keychain_delete":
        return "keychain 삭제는 되돌릴 수 없음 — 필요 시 다시 로그인"
    return f"no rollback for {kind}"


NEW_OPS = {"write_block", "remove_external", "write_file", "remove_file", "registry_put",
           "registry_delete", "keychain_delete"}


# ─────────────────────────── accounts 요약 ───────────────────────────


def accounts_summary(registry: str | None) -> dict:
    reg = registry_load(registry_path(registry))
    targets = detect_targets()
    exts = scan_externals(targets)
    by_name: dict[str, list] = {}
    for e in exts:
        by_name.setdefault(e["name"], []).append(e)
    externals = []
    for name, es in sorted(by_name.items()):
        sigs = {}
        for e in es:
            if e.get("parseable"):
                sigs.setdefault(signature(e["definition"]), {"definition": e["definition"], "sources": []})
                sigs[signature(e["definition"])]["sources"].append({"file": e["file"], "kind": e["kind"]})
        externals.append({
            "name": name,
            "in_registry": name in reg["accounts"],
            "variants": [{"signature": k, **v} for k, v in sigs.items()],
            "unparseable": [{"file": e["file"], "kind": e["kind"], "reason": e.get("reason")}
                            for e in es if not e.get("parseable")],
        })
    return {"os": ap_os(), "targets": targets, "registry": reg, "externals": externals}


# ─────────────────────────── CLI ───────────────────────────


def _opts(argv: list[str]) -> dict:
    o: dict = {}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--"):
            key = a[2:].replace("-", "_")
            if i + 1 < len(argv) and not argv[i + 1].startswith("--"):
                o[key] = argv[i + 1]
                i += 2
            else:
                o[key] = True
                i += 1
        else:
            o.setdefault("_pos", []).append(a)
            i += 1
    return o


def _kv(csv: str | None) -> dict:
    out = {}
    for part in (csv or "").split(","):
        if "=" in part:
            k, v = part.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def _account_for(name: str, registry: str | None) -> dict:
    reg = registry_load(registry_path(registry))
    if name in reg["accounts"]:
        return reg["accounts"][name]
    raise SystemExit(f"registry 에 '{name}' 이(가) 없습니다.")


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 1
    cmd, rest = argv[0], argv[1:]
    out = sys.stdout
    if cmd == "os":
        print(ap_os())
    elif cmd == "npath":
        print(npath(rest[0]))
    elif cmd == "targets":
        t = detect_targets()
        print(json.dumps({"targets": t, "warnings": target_warnings(t)}, ensure_ascii=False, indent=2))
    elif cmd == "render":
        print("\n".join(render(rest[0], json.loads(rest[1]).get("name", "x"), json.loads(rest[1]))))
    elif cmd == "accounts":
        o = _opts(rest)
        print(json.dumps(accounts_summary(o.get("registry")), ensure_ascii=False, indent=2))
    elif cmd == "plan-add":
        o = _opts(rest)
        plan = plan_add(o["name"], o.get("mode", "standard"), o.get("config_dir") or f"~/.claude-{o['name']}",
                        o.get("token_dir"), o.get("shared_pool"),
                        [s for s in str(o.get("shared") or "").split(",") if s and s is not True],
                        _kv(o.get("extra_env")), bool(o.get("manual")), o.get("registry"))
        print(json.dumps(plan, ensure_ascii=False, indent=2))
    elif cmd == "plan-adopt":
        o = _opts(rest)
        print(json.dumps(plan_adopt(o["name"], o.get("signature"), o.get("registry"), o.get("from_kind")),
                         ensure_ascii=False, indent=2))
    elif cmd == "plan-unlink":
        o = _opts(rest)
        print(json.dumps(plan_unlink(o["name"], o.get("registry")), ensure_ascii=False, indent=2))
    elif cmd == "env":
        o = _opts(rest)
        acct = _account_for(o["_pos"][0], o.get("registry"))
        for k, v in resolved_env(acct).items():
            print(f"{k}={'' if v is None else v}")
    elif cmd == "run":
        if "--" not in rest:
            raise SystemExit("usage: aplib.py run <name> [--registry R] -- <cmd...>")
        idx = rest.index("--")
        o = _opts(rest[:idx])
        acct = _account_for(o["_pos"][0], o.get("registry"))
        env = dict(os.environ)
        for k, v in resolved_env(acct).items():
            if v is None:
                env.pop(k, None)
            else:
                env[k] = v
        argv2 = rest[idx + 1:]
        exe = shutil.which(argv2[0]) or argv2[0]
        return subprocess.run([exe] + argv2[1:], env=env).returncode
    elif cmd == "apply-op":
        op = json.loads(rest[0] if rest else sys.stdin.read())
        print(json.dumps(apply_op(op), ensure_ascii=False))
    elif cmd == "rollback-op":
        op = json.loads(rest[0] if rest else sys.stdin.read())
        print(rollback_op(op))
    elif cmd == "block-write":
        # block-write <file> <name> <kind> <account-json>
        f, name, kind, aj = rest
        acct = json.loads(aj)
        block_write(f, name, render(kind, name, acct))
    elif cmd == "block-remove":
        print("removed" if block_remove(rest[0], rest[1]) else "absent")
    elif cmd == "block-list":
        for n in list_blocks(rest[0]):
            print(n)
    elif cmd == "externals":
        kind = rest[1] if len(rest) > 1 else "posix"
        print(json.dumps(parse_rc_externals(rest[0], kind), ensure_ascii=False, indent=2))
    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        return 1
    out.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
