#!/usr/bin/env bash
# 단위 테스트 전체 실행.
# 사용: bash tests/unit/run.sh
set -uo pipefail

cd "$(dirname "$0")"

# 결정적 테스트: 실제 셸 대상 감지(PowerShell 질의 등)를 끈다. 개별 테스트가 필요 시 덮어쓴다.
export AP_TARGETS="${AP_TARGETS:-[]}"

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_FILES=()

shopt -s nullglob
for test_file in *_test.sh; do
  echo "=== $test_file ==="
  if bash "$test_file"; then
    :
  else
    FAILED_FILES+=("$test_file")
  fi
done

echo ""
echo "=========================="
if [[ ${#FAILED_FILES[@]} -gt 0 ]]; then
  echo "FAILED test files:"
  for f in "${FAILED_FILES[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
echo "All test files passed."
