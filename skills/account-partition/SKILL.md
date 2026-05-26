---
name: account-partition
description: "Claude CLI를 여러 OAuth 계정용으로 분리·관리. 메인 메뉴 dispatcher — 액션 선택 후 해당 sub-skill 호출."
---

# account-partition (메뉴 dispatcher)

이 스킬은 4개 sub-skill로 분기하는 메뉴 dispatcher다. 액션을 알고 있으면 `account-partition:add`·`:list`·`:edit`·`:unlink` 직접 호출이 더 빠름.

## 호출 시 announce

"account-partition 메뉴 dispatcher를 실행할게."

## 메인 메뉴

`AskUserQuestion`:

```
질문: 무엇을 할까요?
옵션:
  - 계정 추가 연동 (account-partition:add)
  - 계정 조회 (account-partition:list)
  - 계정의 공유 항목 수정 (account-partition:edit)
  - 계정 연동 해제 (account-partition:unlink — v1 미지원, 안내만)
```

선택에 따라 해당 sub-skill을 Skill tool로 invoke:
- "계정 추가 연동" → `account-partition:add`
- "계정 조회" → `account-partition:list`
- "계정의 공유 항목 수정" → `account-partition:edit`
- "계정 연동 해제" → `account-partition:unlink`

(각 sub-skill 흐름은 해당 SKILL.md에 자체 완결 정의)
