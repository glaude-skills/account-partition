# account-partition

여러 Claude CLI OAuth 계정을 한 머신에서 `CLAUDE_CONFIG_DIR` alias(예: `claude-work`, `claude-personal`)로 분리하고, 계정 사이의 공유/격리 항목을 사용자가 선택할 수 있게 해주는 Claude Code plugin.

**상태**: v0.4 — 계정 추가 연동 / 계정 조회 / 계정의 공유 항목 수정 / OAuth 로그인·로그아웃 / **계정 연동 해제(unlink) 자동화** 지원. 외부 alias 자동 수정은 후속으로 이연.
**플랫폼**: macOS + zsh (1차)

## 설치

새 Claude Code 세션에서:

```
/plugin marketplace add glaude-skills/account-partition
/plugin install account-partition@account-partition
```

## 사용

메뉴에서 선택:

```
/account-partition
```

또는 액션 직접 호출:

```
/account-partition:add          # 계정 추가 연동
/account-partition:list         # 계정 조회 (공유/격리 매트릭스)
/account-partition:edit         # 공유 항목 수정
/account-partition:login        # OAuth 로그인 (v0.3+)
/account-partition:logout       # OAuth 로그아웃 (v0.3+)
/account-partition:unlink       # 연동 해제 — v0.4부터 자동화
```

## UX 원칙

- 자유 텍스트 입력은 **명령어 이름 단 1곳만** (예: `side` → `claude-side`)
- 그 외 모든 결정(메뉴·프리셋·항목 토글·yes/no 확인·충돌 해결)은 객관식 (방향키 + 엔터)

## 안전장치

- 모든 파괴적 변경은 **operation plan** 객체로 구성 → 미리보기·드라이런·실행·롤백이 모두 같은 plan에서
- **활성 세션 게이트** — 다른 Claude 프로세스가 같은 `CLAUDE_CONFIG_DIR`를 점유 중이면 변경 차단
- **계정별 lockfile** — 동시 호출 방지
- **격리 보존** — 충돌 사본은 즉시 삭제 아닌 `.account-partition-quarantine/`으로 이동
- **`settings.json` 격리 강제** — MCP 토큰 등 시크릿이 전 계정에 전파되지 않게

## 디자인 / 구현 계획

- `skills/account-partition/design.md` — 디자인 (리비전 3)
- `skills/account-partition/plan.md` — 구현 계획

## License

MIT
