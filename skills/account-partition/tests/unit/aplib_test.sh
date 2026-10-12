#!/usr/bin/env bash
# v0.5: 멀티 OS 렌더링, 블록 편집(인코딩 보존), 외부 정의 파서, adopt / token-only add / unlink plan 실행·롤백.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/assert.sh"
SCRIPTS="$SCRIPT_DIR/../../scripts"
source "$SCRIPTS/platform.sh"

sb=$(make_sandbox)
trap 'cleanup_sandbox "$sb"' EXIT

AP() { bash "$SCRIPTS/ap.sh" "$@"; }
PY() { python3 -c "import sys,os; sys.path.insert(0, os.path.dirname(os.environ['AP_LIB'])); import aplib; $1"; }

TOK='{"name":"dami","mode":"token-only","config_dir":"~/.claude-work","token_dir":"~/.claude-dami","extra_env":{"CLAUDE_PROFILE":"dami"}}'
STD_DEFAULT='{"name":"han","mode":"standard","config_dir":"~/.claude","token_dir":null}'

echo "── 렌더링 (OS mock)"
out=$(AP_OS_OVERRIDE=macos AP render posix "$TOK")
assert_contains "$out" '# >>> account-partition: dami >>>' "posix 시작 마커"
assert_contains "$out" 'env -u CLAUDE_CONFIG_DIR -u CLAUDE_SECURESTORAGE_CONFIG_DIR CLAUDE_CONFIG_DIR="$HOME/.claude-work" CLAUDE_SECURESTORAGE_CONFIG_DIR="$HOME/.claude-dami" CLAUDE_PROFILE=dami claude "$@"' "posix(macOS) token-only 본문"
out=$(AP_OS_OVERRIDE=windows AP render posix "$TOK")
assert_contains "$out" 'CLAUDE_CONFIG_DIR="$USERPROFILE\.claude-work"' "posix(Windows) 는 USERPROFILE 네이티브 경로"
out=$(AP_OS_OVERRIDE=linux AP render posix "$STD_DEFAULT")
if [[ "$out" == *'CLAUDE_CONFIG_DIR="'* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 기본 계정은 CLAUDE_CONFIG_DIR 를 설정하면 안 됨"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 기본 계정(~/.claude)은 CLAUDE_CONFIG_DIR unset (macOS 키체인 이름 보존)"
fi
out=$(AP_OS_OVERRIDE=windows AP render powershell "$TOK")
assert_contains "$out" "[Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', (Join-Path \$HOME '.claude-work'), 'Process')" "PowerShell config 설정"
assert_contains "$out" "[Environment]::SetEnvironmentVariable('CLAUDE_SECURESTORAGE_CONFIG_DIR', (Join-Path \$HOME '.claude-dami'), 'Process')" "PowerShell 토큰 폴더 설정"
assert_contains "$out" '} finally {' "PowerShell try/finally 로 env 복구"
assert_contains "$out" 'Get-Command claude -CommandType Application' "PowerShell 은 실제 실행 파일 호출 (재귀 방지)"
out=$(AP render powershell "$STD_DEFAULT")
assert_contains "$out" "SetEnvironmentVariable('CLAUDE_CONFIG_DIR', \$null, 'Process')" "PowerShell 기본 계정은 \$null (unset)"
out=$(AP render cmd "$TOK")
assert_contains "$out" 'setlocal' "cmd setlocal"
assert_contains "$out" 'set "CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-work"' "cmd config"
assert_contains "$out" 'set "CLAUDE_SECURESTORAGE_CONFIG_DIR=%USERPROFILE%\.claude-dami"' "cmd 토큰 폴더"
out=$(AP render cmd "$STD_DEFAULT")
assert_contains "$out" 'set "CLAUDE_SECURESTORAGE_CONFIG_DIR="' "cmd 상속 토큰 폴더 제거"
out=$(AP_OS_OVERRIDE=linux AP render sh "$TOK")
assert_contains "$out" 'unset CLAUDE_CONFIG_DIR CLAUDE_SECURESTORAGE_CONFIG_DIR' "sh 래퍼 unset"
assert_contains "$out" 'exec claude "$@"' "sh 래퍼 exec"
nonascii=$( { AP render posix "$TOK"; AP render powershell "$TOK"; AP render cmd "$TOK"; AP render sh "$TOK"; } | LC_ALL=C grep -c '[^ -~]' || true)
assert_eq "$nonascii" "0" "생성 블록은 ASCII 전용"

echo "── 블록 편집: 인코딩·줄바꿈 보존"
prof="$sb/profile.ps1"
printf '\xef\xbb\xbf# \xed\x95\x9c\xea\xb8\x80 \xec\xa3\xbc\xec\x84\x9d\r\nfunction touch { }\r\n' > "$prof"
python3 "$AP_LIB" block-write "$prof" dami powershell "$TOK"
head3=$(head -c 3 "$prof" | od -An -tx1 | tr -d ' ')
assert_eq "$head3" "efbbbf" "UTF-8 BOM 보존"
assert_contains "$(cat "$prof")" "한글 주석" "기존 한글 내용 보존"
crlf_lines=$(grep -c $'\r$' "$prof")
total_lines=$(wc -l < "$prof")
assert_eq "$crlf_lines" "$total_lines" "CRLF 줄바꿈 유지 (블록 포함)"
python3 "$AP_LIB" block-write "$prof" dami powershell "$TOK"
assert_eq "$(grep -c 'account-partition: dami >>>' "$prof")" "1" "재기록 시 블록 1개 (idempotent)"
cp949="$sb/cp949.ps1"
printf '# \xc7\xd1\xb1\xdb\n' > "$cp949"   # CP949 '한글'
python3 "$AP_LIB" block-write "$cp949" x powershell "$TOK"
first=$(head -1 "$cp949" | od -An -tx1 | tr -d ' \n')
assert_eq "$first" "2320c7d1b1db0a" "CP949 바이트 그대로 보존"
python3 "$AP_LIB" block-remove "$prof" dami >/dev/null
assert_eq "$(grep -c 'account-partition' "$prof")" "0" "블록 제거"
assert_contains "$(cat "$prof")" "function touch" "블록 밖 내용 보존"

echo "── 외부 정의 파서 (이 PC 실제 형태)"
H="$sb/home"; mkdir -p "$H/bin" "$H/Documents/WindowsPowerShell" "$H/.claude-work" "$H/.claude-dami" "$H/.claude"
PS="$H/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1"
printf '\xef\xbb\xbf' > "$PS"
cat >> "$PS" <<'EOF'
function which {
    Get-Command $args[0] | Select-Object -ExpandProperty Source
}

# 5. Claude Code 호출 명령 (work)
function claude-work {
    $env:CLAUDE_PROFILE = 'work'
    $env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\.claude-work"
    Remove-Item Env:CLAUDE_SECURESTORAGE_CONFIG_DIR -ErrorAction SilentlyContinue
    & claude @args
}

# 6. Claude Code 호출 명령 (dami)
#    로그인 토큰만 ~\.claude-dami 에 따로 저장한다.
function claude-dami {
    $env:CLAUDE_PROFILE = 'dami'
    $env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\.claude-work"
    $env:CLAUDE_SECURESTORAGE_CONFIG_DIR = "$env:USERPROFILE\.claude-dami"
    & claude @args
}

function claude-weird {
    if ($x) { Write-Host hi }
    & claude @args
}
EOF
cat > "$H/bin/claude-dami" <<'EOF'
#!/bin/bash
# claude-dami: 독립 계정
export CLAUDE_PROFILE=dami
export CLAUDE_CONFIG_DIR="$USERPROFILE\.claude-dami"
exec claude "$@"
EOF
printf '@echo off\r\nset CLAUDE_PROFILE=dami\r\nset CLAUDE_CONFIG_DIR=%%USERPROFILE%%\\.claude-dami\r\nclaude %%*\r\n' > "$H/bin/claude-dami.cmd"
printf '@echo off\r\nset CLAUDE_PROFILE=han\r\nset CLAUDE_CONFIG_DIR=%%USERPROFILE%%\\.claude\r\nclaude %%*\r\n' > "$H/bin/claude-han.cmd"
cat > "$H/bin/claude-han" <<'EOF'
#!/bin/bash
export CLAUDE_PROFILE=han
export CLAUDE_CONFIG_DIR="$USERPROFILE\.claude"
exec claude "$@"
EOF
printf 'alias claude-z="CLAUDE_CONFIG_DIR=$HOME/.claude-z command claude"\n' > "$H/.zshrc"

export AP_HOME="$H" USERPROFILE_SAVED="${USERPROFILE:-}"
export AP_TARGETS="[{\"kind\":\"zsh\",\"path\":\"$H/.zshrc\"},{\"kind\":\"powershell\",\"path\":\"$PS\"},{\"kind\":\"cmd\",\"path\":\"$H/bin\"}]"
summ=$(AP accounts --registry "$H/accounts.json")
get() { echo "$summ" | python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }
assert_eq "$(get "print(sorted(e['name'] for e in d['externals']))")" "['dami', 'han', 'weird', 'work', 'z']" "외부 정의 이름 발견"
assert_eq "$(get "e=[x for x in d['externals'] if x['name']=='dami'][0]; print(len(e['variants']))")" "2" "dami: 셸마다 다른 정의 2종 감지"
assert_eq "$(get "e=[x for x in d['externals'] if x['name']=='work'][0]; v=e['variants'][0]['definition']; print(v['config_dir'], v['token_dir'], v['extra_env'])")" "~/.claude-work None {'CLAUDE_PROFILE': 'work'}" "work: config·추가 env 해석"
assert_eq "$(get "e=[x for x in d['externals'] if x['name']=='han'][0]; print(len(e['variants']), e['variants'][0]['definition']['config_dir'])")" "1 ~/.claude" "han: cmd·sh 래퍼 같은 정의, 기본 계정"
assert_eq "$(get "e=[x for x in d['externals'] if x['name']=='weird'][0]; print(len(e['variants']), len(e['unparseable']))")" "0 1" "해석 불가 정의는 unparseable"
assert_eq "$(get "e=[x for x in d['externals'] if x['name']=='z'][0]; print(e['variants'][0]['definition']['config_dir'])")" "~/.claude-z" "zsh alias 해석"

echo "── adopt (dami: PowerShell 쪽 정의로 통일)"
plan=$(AP plan-adopt --name dami --from-kind powershell --registry "$H/accounts.json")
assert_contains "$plan" '"mode": "token-only"' "adopt: token-only 로 판별"
assert_contains "$plan" '"op": "remove_external"' "adopt: 외부 정의 제거 op"
assert_contains "$plan" '"op": "registry_put"' "adopt: registry 등록 op"
echo "$plan" | PLAN_DIR="$sb/state" bash "$SCRIPTS/plan-execute.sh" >/dev/null
assert_eq "$?" "0" "adopt plan 실행 성공"
ps_now=$(cat "$PS")
assert_contains "$ps_now" '# >>> account-partition: dami >>>' "PowerShell 관리 블록 기록"
if [[ "$ps_now" == *'$env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\.claude-work"'*'$env:CLAUDE_SECURESTORAGE_CONFIG_DIR'* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 외부 dami 함수 잔존"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 외부 dami 함수 제거"
fi
assert_contains "$ps_now" 'function claude-work {' "다른 외부 정의(work)는 보존"
if [[ "$ps_now" == *"(dami)"* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ dami 함수 위 주석 잔존"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ dami 함수 바로 위 주석 함께 제거"
fi
assert_contains "$(cat "$H/bin/claude-dami.cmd")" 'CLAUDE_SECURESTORAGE_CONFIG_DIR=%USERPROFILE%\.claude-dami' "cmd 래퍼가 통일된 정의로 교체"
assert_contains "$(cat "$H/bin/claude-dami")" 'account-partition: dami (managed' "sh 래퍼가 관리 래퍼로 교체"
assert_contains "$(cat "$H/.zshrc")" 'claude-dami() {' "zsh 에도 같은 정의 기록"
ls "$H/bin/" | grep -q 'claude-dami.cmd.bak.' && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 기존 래퍼 백업"; } || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 기존 래퍼 백업 없음"; }
reg_mode=$(python3 -c "import json; print(json.load(open(r'$(cygpath -w "$H/accounts.json" 2>/dev/null || echo "$H/accounts.json")'))['accounts']['dami']['token_dir'])")
assert_eq "$reg_mode" "~/.claude-dami" "registry 에 토큰 폴더 기록"
summ=$(AP accounts --registry "$H/accounts.json")
assert_eq "$(get "print(sorted(e['name'] for e in d['externals'] if not e['in_registry']))")" "['han', 'weird', 'work', 'z']" "adopt 후 dami 는 외부 목록에서 빠짐"

echo "── env / run (계정 env 재현)"
envout=$(AP env dami --registry "$H/accounts.json")
assert_contains "$envout" "CLAUDE_PROFILE=dami" "env: 추가 env"
assert_contains "$envout" "CLAUDE_SECURESTORAGE_CONFIG_DIR=" "env: 토큰 폴더"
runout=$(AP run dami --registry "$H/accounts.json" -- "$AP_PYTHON" -c "import os; print(os.environ.get('CLAUDE_SECURESTORAGE_CONFIG_DIR','').endswith('.claude-dami'), os.environ.get('CLAUDE_PROFILE'))")
assert_eq "$runout" "True dami" "run: 계정 env 로 실행"

echo "── token-only add + unlink (공유 config 는 건드리지 않음)"
echo '{"keep":1}' > "$H/.claude-work/.claude.json"
plan=$(AP plan-add --name side --mode token-only --config-dir "$H/.claude-work" --registry "$H/accounts.json")
assert_contains "$plan" '"token_dir"' "plan-add token-only 메타"
assert_contains "$plan" "세션 목록" "token-only 제약 경고 포함"
if [[ "$plan" == *'"create_symlink"'* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ token-only 에 링크 op 가 있음"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ token-only 는 링크를 만들지 않음"
fi
echo "$plan" | PLAN_DIR="$sb/state" bash "$SCRIPTS/plan-execute.sh" >/dev/null
assert_file_exists "$H/.claude-side" "토큰 폴더 생성"
echo 'secret' > "$H/.claude-side/.credentials.json"
plan=$(AP plan-unlink --name side --registry "$H/accounts.json")
if [[ "$plan" == *'"auth_logout"'* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ token-only unlink 에 auth_logout (공유 .claude.json 손상 위험)"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ token-only unlink 는 auth_logout 대신 토큰 폴더 아카이브"
fi
echo "$plan" | PLAN_DIR="$sb/state" bash "$SCRIPTS/plan-execute.sh" >/dev/null
[[ ! -e "$H/.claude-side" ]] && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 토큰 폴더 제거"; } || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 토큰 폴더 잔존"; }
ls -a "$H" | grep -q '^.claude-side.removed.*tar.gz$' && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 토큰 폴더 아카이브"; } || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 아카이브 없음"; }
assert_eq "$(cat "$H/.claude-work/.claude.json")" '{"keep":1}' "공유 config 폴더는 그대로"
if grep -q 'account-partition: side' "$PS" "$H/.zshrc"; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ side 블록 잔존"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 모든 셸에서 side 블록 제거"
fi

echo "── 기본 계정(~/.claude)에 이름 붙이기"
mkdir -p "$H/.claude"; echo 'tok' > "$H/.claude/.credentials.json"
plan=$(AP plan-add --name main --mode standard --config-dir "$H/.claude" --shared plugins --registry "$H/accounts.json")
if [[ "$plan" == *'"create_dir"'* || "$plan" == *'"create_symlink"'* || "$plan" == *'"dir_absent"'* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 기본 계정 add 가 폴더·링크를 건드림"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 기본 계정 add 는 폴더·링크를 만들지 않음"
fi
echo "$plan" | PLAN_DIR="$sb/state" bash "$SCRIPTS/plan-execute.sh" >/dev/null
runout=$(CLAUDE_CONFIG_DIR=x CLAUDE_SECURESTORAGE_CONFIG_DIR=y AP run main --registry "$H/accounts.json" -- "$AP_PYTHON" -c "import os; print('CLAUDE_CONFIG_DIR' in os.environ, 'CLAUDE_SECURESTORAGE_CONFIG_DIR' in os.environ)")
assert_eq "$runout" "False False" "기본 계정 run: 두 env 모두 지움"
plan=$(AP plan-unlink --name main --registry "$H/accounts.json")
if [[ "$plan" == *'"auth_logout"'* || "$plan" == *'"archive_dir"'* || "$plan" == *'"remove_dir"'* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 기본 계정 unlink 가 로그아웃·폴더 정리를 함"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 기본 계정 unlink 는 셸 정의만 제거"
fi
echo "$plan" | PLAN_DIR="$sb/state" bash "$SCRIPTS/plan-execute.sh" >/dev/null
assert_eq "$(cat "$H/.claude/.credentials.json")" "tok" "기본 계정 토큰 보존"

echo "── unlink 안전장치"
AP plan-adopt --name work --registry "$H/accounts.json" | PLAN_DIR="$sb/state" bash "$SCRIPTS/plan-execute.sh" >/dev/null
out=$(AP plan-unlink --name work --registry "$H/accounts.json" 2>&1)
assert_contains "$out" "claude-dami" "기준 계정(work) unlink 는 token-only 의존 계정(dami) 때문에 거부"
AP plan-adopt --name han --registry "$H/accounts.json" | PLAN_DIR="$sb/state" bash "$SCRIPTS/plan-execute.sh" >/dev/null
out=$(AP plan-unlink --name han --registry "$H/accounts.json")
if [[ "$out" == *'"auth_logout"'* || "$out" == *'"archive_dir"'* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 기본 계정 unlink 가 로그아웃/아카이브를 포함"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 기본 계정(~/.claude) unlink 는 셸 정의만 제거"
fi
assert_contains "$(cat "$H/bin/claude-han.cmd")" 'set "CLAUDE_CONFIG_DIR="' "han(기본 계정) 래퍼는 CLAUDE_CONFIG_DIR unset"

echo "── 실패 시 롤백 (write 계열 op)"
before_ps=$(md5sum < "$PS")
bad='{"operations":[{"op":"write_block","file":"'"$PS"'","kind":"powershell","name":"rb","lines":["# >>> account-partition: rb >>>","# <<< account-partition: rb <<<"],"backup":true},{"op":"create_symlink","src":"'"$sb"'/nope","dst":"'"$sb"'/x"}]}'
echo "$bad" | PLAN_DIR="$sb/state2" bash "$SCRIPTS/plan-execute.sh" >/dev/null 2>&1
assert_eq "$?" "2" "중간 실패 → exit 2"
PLAN_DIR="$sb/state2" bash "$SCRIPTS/plan-rollback.sh" >/dev/null 2>&1
assert_eq "$(md5sum < "$PS")" "$before_ps" "롤백 후 프로필 원상 복구"

echo "── 리뷰 회귀: 파서·줄바꿈·unlink 보호"
R="$sb/review"; mkdir -p "$R"
# #3 한 줄 함수 헤더 + 다음 줄 닫는 괄호 + ${HOME}
printf 'export KEEP=1\nclaude-r3() { env CLAUDE_CONFIG_DIR="${HOME}/.claude-work" claude "$@"\n}\nexport AFTER=1\n' > "$R/r3.sh"
ext=$(python3 "$AP_LIB" externals "$R/r3.sh" posix)
assert_eq "$(echo "$ext" | python3 -c "import json,sys; e=json.load(sys.stdin)[0]; print(e['start'], e['end'], e['parseable'])")" "1 2 True" "\${HOME} 가 있는 함수의 끝 줄을 정확히 찾음"
# #4 PowerShell: 들여쓴 함수 + 바깥 if 블록
printf 'if ($true) {\n    function claude-r4 {\n        $env:CLAUDE_CONFIG_DIR = "$HOME\\.claude-r4"\n        & claude @args\n    }\n    $env:OTHER = 1\n}\n' > "$R/r4.ps1"
ext=$(python3 "$AP_LIB" externals "$R/r4.ps1" powershell)
assert_eq "$(echo "$ext" | python3 -c "import json,sys; e=json.load(sys.stdin)[0]; print(e['start'], e['end'], sorted(e['definition']['extra_env']))")" "1 4 []" "들여쓴 PowerShell 함수의 짝 괄호에서 끝남 (바깥 코드 흡수 안 함)"
# #5 블록 주석 / 다른 도구 마커는 흡수하지 않음
printf '<#\n doc\n#>\nfunction claude-r5 {\n    & claude @args\n}\n' > "$R/r5.ps1"
assert_eq "$(python3 "$AP_LIB" externals "$R/r5.ps1" powershell | python3 -c "import json,sys; e=json.load(sys.stdin)[0]; print(e['comment_start'])")" "3" "PowerShell 블록 주석(#>) 흡수 안 함"
printf '# <<< conda initialize <<<\nclaude-r5b() { claude "$@"; }\n' > "$R/r5b.sh"
assert_eq "$(python3 "$AP_LIB" externals "$R/r5b.sh" posix | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['comment_start'])")" "1" "다른 도구 마커(# <<<) 흡수 안 함"
printf '# 관련 없는 설명\nclaude-r5c() { claude "$@"; }\n' > "$R/r5c.sh"
assert_eq "$(python3 "$AP_LIB" externals "$R/r5c.sh" posix | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['comment_start'])")" "1" "이름 언급 없는 주석은 흡수 안 함"
# #6 LF 파일에 CRLF 한 줄 → 다른 줄은 LF 유지
printf 'export A=1\nexport B=2\r\nexport C=3\n' > "$R/r6.sh"
python3 "$AP_LIB" block-write "$R/r6.sh" r6 posix "$TOK"
assert_eq "$(PY "print(open(aplib.npath(r'$R/r6.sh'),'rb').read().count(b'\r'))")" "1" "원래 CRLF 였던 한 줄만 CRLF (파일 전체 변환 안 함)"
# #7 함수 본문 안 'VAR=값 claude "$@"' 형태
printf 'claude-r7() {\n  CLAUDE_CONFIG_DIR="$HOME/.claude-r7" claude "$@"\n}\n' > "$R/r7.sh"
assert_eq "$(python3 "$AP_LIB" externals "$R/r7.sh" posix | python3 -c "import json,sys; e=json.load(sys.stdin)[0]; print(e['parseable'], e['definition']['config_dir'])")" "True ~/.claude-r7" "VAR=값 claude \"\$@\" 형태 해석"
# 경로 접두 오인 ($HOMEBREW_PREFIX)
assert_eq "$(PY "print(aplib._norm_value_path('\$HOMEBREW_PREFIX/x').startswith('~'))")" "False" "\$HOMEBREW_PREFIX 를 홈으로 오인하지 않음"
# #1 token_dir 이 다른 계정 폴더면 unlink 가 지우지 않음
RG="$R/reg.json"
PY "aplib.registry_save(r'$RG', {'version':1,'accounts':{'w':{'mode':'standard','config_dir':'~/.claude-work','token_dir':None,'targets':[]},'x':{'mode':'token-only','config_dir':'~/.claude','token_dir':'~/.claude-work','targets':[]}}})"
out=$(AP plan-unlink --name x --registry "$RG")
if [[ "$out" == *'"remove_dir"'* || "$out" == *'"archive_dir"'* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 다른 계정 폴더를 토큰 폴더로 쓰는 계정 unlink 가 그 폴더를 지움"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 토큰 폴더가 다른 계정 폴더면 지우지 않음"
fi
PY "aplib.registry_save(r'$RG', {'version':1,'accounts':{'x':{'mode':'token-only','config_dir':'~/.claude-work','token_dir':'~/.claude','targets':[]}}})"
out=$(AP plan-unlink --name x --registry "$RG")
if [[ "$out" == *'"remove_dir"'* ]]; then
  ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  ✗ 토큰 폴더가 ~/.claude 인데 삭제"
else
  ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ✓ 토큰 폴더가 기본 계정(~/.claude)이면 지우지 않음"
fi
# #8 링크가 들어 있는 아카이브 복원
mkdir -p "$R/pool/plugins" "$R/acct"; echo p > "$R/pool/plugins/a"; echo own > "$R/acct/own.txt"
PY "aplib.make_link(r'$R/pool/plugins', r'$R/acct/plugins')"
echo '{"operations":[{"op":"archive_dir","src":"'"$R/acct"'"},{"op":"remove_dir","path":"'"$R/acct"'"},{"op":"create_symlink","src":"'"$R"'/nope","dst":"'"$R"'/x"}]}' | PLAN_DIR="$R/st" bash "$SCRIPTS/plan-execute.sh" >/dev/null 2>&1
PLAN_DIR="$R/st" bash "$SCRIPTS/plan-rollback.sh" >/dev/null 2>&1
assert_eq "$(cat "$R/acct/own.txt" 2>/dev/null)" "own" "unlink 롤백: 계정 폴더 복원"
assert_eq "$(cat "$R/acct/plugins/a" 2>/dev/null)" "p" "unlink 롤백: 공유 링크 복원"
assert_file_exists "$R/pool/plugins/a" "아카이브·삭제 중 공유 원본 보존"

echo "── 링크: junction/symlink 제거 시 대상 보존"
mkdir -p "$sb/pool/plugins"; echo keep > "$sb/pool/plugins/f.txt"; mkdir -p "$sb/acct"
PY "aplib.make_link(r'$sb/pool/plugins', r'$sb/acct/plugins'); aplib.remove_tree(r'$sb/acct')"
assert_file_exists "$sb/pool/plugins/f.txt" "링크 디렉토리 삭제 시 공유 원본 내용 보존"

unset AP_HOME
print_summary
