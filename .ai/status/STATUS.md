# 진행 상태

## 현재: v0.5.2 (2026-10-27)

- v0.5.2: 래퍼가 `attach` 를 가로챈다. 세션을 띄운 토큰 폴더(`jobs/<id>/state.json` 의 `providerEnv`)와 지금 계정이 다르면 세션을 멈추고 이 계정으로 포그라운드 `--resume` 한다. 헬퍼는 `~/.claude-shared/ap_attach.py` (plan 이 UTF-8 로 설치). 2.1.311 실측: `--bg --resume` 은 저장된 토큰 폴더를 다시 쓰고, 플래그를 붙이면 복사본이 생겨 쓸 수 없음

## v0.5.1 (2026-10-12)

- v0.5.1: add 에 "지금 계정에 이름 붙이기" 추가. 기본 계정(`~/.claude`)을 폴더·로그인 변경 없이 `claude-<이름>` 으로도 부른다. 토큰을 다른 폴더로 복사하면 refresh 토큰 회전으로 한쪽이 끊기므로 복사하지 않는다

## v0.5.0 (2026-10-12)

- spec: `docs/work/multi-os-token-partition/design.md`
- 완료
  - 플랫폼 계층(`platform.sh`, `aplib.py`): macOS/Linux/Windows(Git Bash), Python UTF-8 강제, MSYS 경로 변환, junction 안전 링크
  - 셸 4종(zsh/bash/PowerShell/cmd 래퍼) 동시 기록, env 누수 차단
  - 토큰만 분리 모드(`CLAUDE_SECURESTORAGE_CONFIG_DIR`), adopt sub-skill, registry(`~/.claude-shared/accounts.json`)
  - unlink 안전장치: 공유 config 보호, 기본 계정 보호, token-only 는 토큰 폴더만 정리
- 검증
  - 단위 테스트 전체 통과: Windows(Git Bash), Linux(Docker python:3.12-slim)
  - 실기: Windows 11 + PowerShell 5.1 + cmd + Git Bash 에서 adopt(work/han/dami) 후 env·토큰 주인 확인, Linux 컨테이너 bash/zsh 실행 확인
  - macOS: OS mock 단위 테스트만. 실기 재검증 필요

## 알려진 제약

- 토큰만 분리 모드에서 Claude Code 화면 안의 세션 목록(←←)으로 다른 계정이 띄운 세션에 참여하면 그 세션을 띄운 계정 토큰이 쓰인다. 셸의 `claude-<이름> attach` 만 래퍼가 막는다
- `CLAUDE_SECURESTORAGE_CONFIG_DIR` 은 문서화되지 않은 내부 변수 (2.1.292 기준)

## 다음 후보 (v0.6+)

- macOS 실기 재검증 (zsh 블록, 키체인 이름, `keychain_delete`)
- Codex 리뷰 P1-2(활성 세션 게이트 정밀도), P1-4(`claude auth` feature-detect), P2(SKILL 템플릿 통일, CHANGELOG)
- fish 자동 기록
- edit 흐름의 registry 연동 (현재는 `~/.claude-<name>` 경로 가정)
