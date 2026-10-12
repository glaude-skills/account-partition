# account-partition — 프로젝트 컨텍스트

여러 Claude CLI OAuth 계정을 한 머신에서 셸 명령(`claude-<name>`)으로 분리·관리하는 Claude Code 플러그인. 메뉴 dispatcher(`skills/account-partition`) + sub-skill 7개(add, list, edit, adopt, login, logout, unlink).

## 구조

- `skills/*/SKILL.md`: LLM이 따라가는 흐름. 모든 결정은 `AskUserQuestion` 객관식, 자유 입력은 명령어 이름 1곳만.
- `skills/account-partition/scripts/`: 헬퍼. 모든 bash 헬퍼는 `platform.sh`를 source하고, 핵심 로직은 `aplib.py`(셸 블록, 외부 정의 파서, registry, plan 연산).
- `skills/account-partition/tests/unit/run.sh`: 단위 테스트 전체 실행.
- 계정 단일 원본: `~/.claude-shared/accounts.json`. 셸 파일은 결과물.

## 작업 규칙

- main 브랜치에 직접 commit + push (플러그인 배포 = main). 변경마다 `.claude-plugin/plugin.json`과 `marketplace.json` 버전을 올린다.
- 커밋 메시지에 AI 트레일러(Co-Authored-By 등)를 넣지 않는다.
- 커밋 전 `bash skills/account-partition/tests/unit/run.sh` 전체 통과.
- 작업 단위가 끝나면 `.ai/status/STATUS.md`를 같은 커밋에서 갱신.

## 라우팅

| 트리거 | 먼저 읽을 문서 | 잊지 말 것 |
|---|---|---|
| 셸 블록·렌더링·파서 수정 (`aplib.py`, `shell-rc.sh`) | `docs/work/multi-os-token-partition/design.md` §5, §6 | 생성 블록은 ASCII 전용, 파일 편집은 바이트 수준, Windows 경로는 `USERPROFILE` 기반 네이티브 문자열 |
| 토큰 분리·로그인·unlink (`CLAUDE_SECURESTORAGE_CONFIG_DIR`) | 같은 문서 §3, §7 | 기본 계정은 `CLAUDE_CONFIG_DIR`를 설정하지 말고 unset (macOS 키체인 이름이 달라짐) |
| 링크·삭제 연산 (`plan-execute.sh`, `plan-rollback.sh`) | 같은 문서 §8 | Windows junction은 `rm -rf` 금지, `os.rmdir`로 제거 |
| 기존 v0.4 설계 맥락 | `skills/account-partition/design.md` | `settings.json`은 격리 강제 항목 |
