# 수동 검증 시나리오

자동 단위 테스트로 커버하지 못하는 부분(SKILL.md 자연어 흐름, 실제 ~/.claude* 환경 통합)을 수동 시나리오로 검증합니다.

## 사전 준비

새 Claude Code 세션(또는 현재 세션). 플러그인 install 상태:

```
/plugin marketplace add glaude-skills/account-partition
/plugin install account-partition@account-partition
/reload-plugins
```

## MV-1: Add (기본 분리 프리셋)

**목적**: 새 alias `claude-test1` 추가, 기본 분리 프리셋 검증

1. `/account-partition`
2. "계정 추가 연동" 선택
3. 명령어 이름: `test1`
4. "기본 분리" 선택
5. 공유 보관소 위치: `~/.claude-shared` 그대로
6. 셸 통합: "자동 추가 + 백업"
7. 미리보기 후 "예 (실행)"

**기대 결과**:
- `~/.claude-test1/` 생성
- `~/.claude-test1/{plugins,skills,commands,agents}/` 각각 `~/.claude-shared/`로 심볼릭
- `~/.zshrc`에 marker + alias 라인 추가
- `~/.zshrc.bak.*` 백업 생성
- 다음 단계 안내 (source ~/.zshrc, /login)

**검증**:
- `ls -la ~/.claude-test1/`
- `grep -A1 'account-partition: test1' ~/.zshrc`
- 새 터미널: `claude-test1` 실행 → CC 정상 시작 → /login으로 첫 로그인

## MV-2: Add (완전 격리)

**목적**: 공유 0개 검증

1. `/account-partition` → "계정 추가 연동" → 명령어 이름 `test2` → "완전 격리"
2. (이하 동일)

**기대 결과**:
- `~/.claude-test2/` 생성, 안에 심볼릭 0개
- alias만 ~/.zshrc에

## MV-3: Add (직접 선택 — 플러그인만)

**목적**: 직접 선택 흐름 + 부분 공유

1. `/account-partition` → 명령어 이름 `test3` → "직접 선택" → 플러그인만 체크
2. 진행

**기대 결과**:
- `~/.claude-test3/plugins` symlink 1개만, 다른 디렉토리는 자체 없음

## MV-4: List 매트릭스 정확성

**목적**: 매트릭스 정확성 + 시크릿 경고

전제: MV-1·2·3 이미 진행됨.

1. `/account-partition` → "계정 조회"

**기대 결과**:
- 등록된 모든 alias 표시
- test1: 플러그인·스킬·슬래시 명령·서브에이전트 = `● 공유`
- test2: 모두 `자체` 또는 `─`
- test3: 플러그인만 `● 공유`, 나머지 `자체` 또는 `─`
- (사용자 환경의 work·personal이 settings.json을 공유 중이면) `전역 설정` row에 `⚠ 공유` 표시

## MV-5: Edit (격리 → 공유)

**목적**: test1의 글로벌 인스트럭션을 공유로 전환

1. `~/.claude-test1/CLAUDE.md` 생성 (수동): `echo "# test1 instructions" > ~/.claude-test1/CLAUDE.md`
2. `/account-partition` → "계정의 공유 항목 수정" → test1 선택
3. multiSelect에서 "글로벌 인스트럭션" 추가 체크 → 진행

**기대 결과**:
- 충돌 없으면 (공유 보관소에 CLAUDE.md 없으면) 그대로 진행
- 충돌 있으면 `AskUserQuestion` 3지 선택
- 진행 후 `~/.claude-test1/CLAUDE.md` → `~/.claude-shared/CLAUDE.md` symlink
- 원본은 `~/.claude-test1/.account-partition-quarantine/CLAUDE.md.<ts>` 로 격리 보존

## MV-6: Edit (공유 → 격리)

**목적**: test1의 plugins를 격리로 전환

1. `/account-partition` → "공유 항목 수정" → test1 → 플러그인 체크 해제

**기대 결과**:
- symlink 제거 + 공유 본 복사 → `~/.claude-test1/plugins/` 자체 디렉토리

## MV-7: 충돌 처리

**목적**: 공유 본 충돌 시 3지 옵션 동작

전제: test2도 CLAUDE.md 자체 있고, 공유 보관소에도 다른 CLAUDE.md 있음.

1. `/account-partition` → "공유 항목 수정" → test2 → 글로벌 인스트럭션 체크
2. 충돌 발견 → `AskUserQuestion` 3지

**검증**:
- "공유 본 보존" → test2 사본을 quarantine으로 이동
- "사본으로 덮어쓰기" → 영향 alias 목록 + 추가 확인
- "이 항목만 변경 취소" → plan에서 제외

## MV-8: 활성 세션 게이트

**목적**: 다른 Claude 세션 실행 중 변경 차단

1. test1을 `claude-test1` 실행하고 그대로 두기
2. 다른 세션에서 `/account-partition` → "공유 항목 수정" → test1 선택

**기대 결과**: 변경 작업 시도 시 활성 세션 감지 → 차단 + 안내.

## MV-9: 롤백 (실패 주입)

**목적**: 부분 진행 후 자동 롤백

1. 새 alias `test_rb` 추가 시도. 단 사전에 `~/.claude-test_rb/` 자체를 `chmod 000`으로 만들어 권한 차단
2. plan-execute 부분 실행 → 권한 실패 → 자동 롤백

**기대 결과**:
- 일부 완료된 op (아마 create_dir만) 역순 되돌림
- 상태 파일 archive (`.rolled-back.<ts>`로 rename)
- 사용자에게 실패 보고

## MV-10: 드라이런 (명령 출력만)

**목적**: 실제 변경 없이 plan 확인

1. `/account-partition` → "계정 추가 연동" → 명령어 이름 임시 → 진행 → 미리보기 후 "명령 출력만"

**기대 결과**:
- 셸 명령 시퀀스 (mkdir·ln -s·echo) 출력
- 실제 디스크 변경 0건
- ~/.zshrc 변동 0줄
- 동일 명령을 사용자가 직접 실행하면 같은 결과

## MV-11: 정리

테스트로 만든 `test1`, `test2`, `test3`, `test_rb` 모두 수동 정리:

```bash
# zshrc alias 라인 제거 (스킬이 만든 marker 블록 직접 sed)
for n in test1 test2 test3 test_rb; do
  bash ~/.claude-shared/plugins/cache/account-partition/account-partition/0.1.0/skills/account-partition/scripts/shell-rc.sh remove ~/.zshrc "$n"
done

# 디렉토리 백업 + 제거
for n in test1 test2 test3 test_rb; do
  [ -d ~/.claude-$n ] && tar czf ~/.claude-$n.removed.$(date +%Y%m%d-%H%M%S).tar.gz -C ~/ .claude-$n && rm -rf ~/.claude-$n
done

# (선택) keychain entry — Phase A.2 fallback이라 자동 매칭 안 됨. 알아서 정리.
```

## 결과 기록

각 시나리오 결과는 별도 파일이나 issue에 기록. v1 합격선:
- MV-1, 2, 3, 4, 10 = 필수 통과
- MV-5, 6, 7 = 핵심 흐름, 통과 권장
- MV-8 = 안전장치, 통과 권장
- MV-9 = 실패 회복, 통과 권장
- MV-11 = 정리 절차, 환경 복원
