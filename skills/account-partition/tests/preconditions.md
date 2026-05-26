# 구현 전 검증 결과

## 검증 1: 슬래시 명령 발견 경로

검증일: 2026-05-26
검증자: gang (사용자)

### 사전 조건

- repo가 GitHub에 push되어 있고 `glaude-skills/account-partition` marketplace로 add됨
- `/plugin install account-partition@account-partition` 실행 완료
- `/reload-plugins`로 등록 활성화 필요

### 검증 절차

같은 Claude Code 세션에서:
1. `/plugin marketplace add glaude-skills/account-partition` (※ `gh:` prefix 없이)
2. `/plugin install account-partition@account-partition`
3. `/reload-plugins` ← 새 plugin install 후 필수
4. `/account-partition:account-partition` 실행 → SKILL.md placeholder 메시지 출력 확인

### 결과

**통과** ✓

- `/account-partition:account-partition` 노출: ✓ 자동완성 잡힘
- `/account-partition` 짧은 이름 노출: (별도 검증 안 함, namespace prefix로 호출 성공)
- SKILL.md placeholder 메시지 출력: ✓ 정상 출력
- 첫 install 시 cache 경로: `~/.claude-work/plugins/marketplaces/glaude-skills-account-partition--plugin-install-account-partition/` (사용자 환경이 claude-work alias라 `.claude-work` 하위)
- `/reload-plugins` 후: 3 plugins · 11 skills · 8 agents · 4 hooks · 0 MCP · 0 LSP

### 메모

- **첫 시도 실패**: 사용자가 `gh:glaude-skills/account-partition`로 입력해 "Invalid marketplace source format" 에러. CC의 marketplace add는 `gh:` prefix를 거부하고 `owner/repo` 형식만 받음. 디자인 문서·README의 안내를 모두 수정 후 재시도하여 성공.
- **SSH key 미설정 영향**: marketplace add가 `git@github.com:...` SSH URL로 clone 시도하다 "Permission denied (publickey)"로 실패하는 케이스가 한 번 있었음. 사용자 ssh-agent에 키가 안 올라간 상태가 원인 추정. 그러나 `owner/repo` 형식으로 다시 시도하니 CC가 HTTPS로 fallback해 성공.
- **install 후 `/reload-plugins` 필수**: install만으로는 슬래시 명령·스킬 발견 안 됨. CC의 plugin 시스템은 lazy load 아니고 reload 필요.
- **slash command 발견 경로**: fork 루트의 `commands/*.md`가 아니라 **install된 plugin의 cache** 위치에서 발견. 디자인 §5/§18 가설 검증 완료.

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
