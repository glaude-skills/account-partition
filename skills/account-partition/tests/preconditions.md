# 구현 전 검증 결과

## 검증 1: 슬래시 명령 발견 경로

검증일: <YYYY-MM-DD>
검증자: <human>

### 사전 조건

- repo가 GitHub에 push되어 있고 `gh:glaude-skills/account-partition` marketplace로 add됨
- `/plugin install account-partition@account-partition` 실행 완료
- plugin cache 위치(`~/.claude*/plugins/cache/account-partition/account-partition/0.1.0/`)에 `commands/`·`skills/` 디렉토리 노출 확인

### 검증 절차

새 Claude Code 세션에서:
1. `/` 입력 후 자동완성 목록에 `account-partition` (또는 `account-partition:account-partition`) 표시 확인
2. `/account-partition` 실행 → SKILL.md placeholder 메시지(`"account-partition 스킬이 정상적으로 호출되었습니다. (검증용 placeholder)"`) 출력 확인

### 결과

**통과 조건**: 자동완성에 노출 + 호출 시 placeholder 메시지 정상 출력. 짧은 이름과 네임스페이스 prefix 중 한쪽만 잡혀도 "부분 통과"로 메모.

- `/account-partition` 노출: [TBD — 노출됨 / 노출 안 됨]
- `/account-partition:account-partition` 노출: [TBD — 노출됨 / 노출 안 됨]
- SKILL.md placeholder 메시지 출력: [TBD — 정상 / 다른 메시지 / 실행 안 됨]
- plugin cache 경로 확인: [TBD]

### 메모

[발견된 이슈·캐시 갱신 절차·다른 호출 경로 등 기록]

---

## 검증 2: Keychain service 이름 hash 규칙

(Task A.2에서 채울 예정 — 양식만 생성)

검증일: <YYYY-MM-DD>

### 알고리즘
- 해시 함수: [TBD — SHA-256 / MD5 / CRC32 / 기타]
- 입력 정규화: [TBD — 절대경로 / ~ 확장 / trailing slash 처리 등]
- 출력 절단: [TBD — suffix 길이]

### 검증 매트릭스

이 검증은 머신·사용자마다 실제 값이 다릅니다. 검증자가 본인 환경의 keychain entry suffix를 캡처해 채워 넣으세요.

| CONFIG_DIR | 실제 suffix | 계산 결과 | 일치 |
|---|---|---|---|
| `~/.claude` | [본인 환경 값] | [본인 환경 값] | [TBD] |
| `~/.claude-<예시>` | [본인 환경 값] | [본인 환경 값] | [TBD] |

`security dump-keychain 2>/dev/null | grep "Claude Code-credentials"` 출력으로 실제 suffix 확인 가능.

### 메모

[버전·OS·CC 빌드 정보, 알 수 없는 변동 요소]
