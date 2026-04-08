---
applyTo: "**"
excludeAgent: "code-review"
---

# AI loop rules

이 규칙층은 "작게 만들고, 사실로 검증하고, 실패하면 안전하게 최대 3번까지만 고친다"는 개인용 실행 규약이다.

## 1. Ground truth first

- 추측으로 구현하지 않는다. 확인 가능한 것은 먼저 확인한다.
- DB 관련 판단은 `Postgres MCP`를 먼저 본다.
- API 계약 관련 판단은 `OpenAPI`를 먼저 본다.
- UI 런타임 문제는 `chrome_devtools`로 먼저 본다.
- 일반 프레임워크/라이브러리 규칙은 `context7`로 먼저 본다.
- OpenAI 관련 기능은 `openaiDeveloperDocs`를 먼저 본다.
- 로컬 코드, 테스트, 타입, 설정이 더 직접적인 진실이면 MCP보다 먼저 본다.

## 2. Small units and completion

- 작업은 endpoint, feature slice, component 단위로 쪼갠다.
- 각 단위는 독립적으로 검증 가능해야 한다.
- 완료 조건:
  - 관련 테스트 통과
  - 관련 빌드/타입체크 통과
  - 필요한 MCP 기준과 로컬 증거가 일치
- 완료 조건이 충족되면 더 넓히지 말고 그 단위를 종료한다.

## 3. Role separation

- Maker와 Checker를 분리한다.
- Codex는 생성과 로컬 수정의 주체가 될 수 있다.
- 최종 아키텍처/보안 승인에는 `critic`, `code-reviewer`, `security-reviewer`, 또는 외부 Gemini 리뷰를 사용한다.
- 한 에이전트가 생성과 최종 승인을 동시에 맡지 않는다.
- 고위험 작업은 구현 후 최소 한 번 별도 리뷰 역할로 pressure-test 한다.

## 4. Auto-fix input and scope

- 품질 게이트나 외부 리뷰 실패를 고칠 때는 먼저 로컬에서 재현 가능한 신호를 수집한다.
- `.ai/gemini-report.json`이 있으면 그 파일을 우선 읽는다.
- GitHub 웹 로그를 무작정 뒤지기보다, 로컬 재현과 요약 보고서부터 본다.
- 수정 우선순위:
  - 보안 취약점
  - 메모리/리소스 누수
  - 아키텍처 결함
  - 기능 회귀
- 단순 스타일/형식 지적만 있고 품질 게이트를 막지 않으면 우선순위를 낮춘다.

## 5. Safe fix loop

- 수정 후 반드시 관련 로컬 테스트 또는 진단을 다시 실행한다.
- `.ai/scripts/gemini-check.mjs`가 존재하면 품질/리뷰 재검증에 포함한다.
- 자동 수정 루프는 최대 3회까지만 반복한다.
- 동일 파일을 같은 문제로 2회 이상 만졌는데도 핵심 오류가 반복되면 루프를 중단한다.
- 같은 실패가 반복되면 무한 루프를 피하고 현재 가설, 시도한 수정, 남은 blocker를 사용자에게 보고한다.

## 6. Push safety and termination

- 에러 수습 중 자동 `git push`는 하지 않는다.
- 필요하면 별도 브랜치에서만 정리한다.
- 모든 테스트와 필수 진단이 통과하면 "푸시 준비 완료" 상태로 보고한다.
- 3회 실패하거나 스스로 해결 불가 판단이면 즉시 사용자 개입을 요청한다.

## 7. MCP speed discipline

- MCP는 기본 1개만 쓴다.
- 첫 번째 MCP로 부족할 때만 두 번째 MCP를 붙인다.
- 문서형 MCP로 런타임 동작을 추정하지 않는다.
- DB 변경이 필요하면 `Postgres MCP`는 확인용으로만 쓰고, 실제 변경은 migration 코드 생성으로 처리한다.

## 8. Reviewer handoff pattern

- 구현 후 최종 확인이 필요하면 아래 우선순위를 따른다.
  - 아키텍처 리스크: `critic`
  - 코드/회귀 리스크: `code-reviewer`
  - 보안 리스크: `security-reviewer`
  - 실제 동작 확인: `qa-tester` 또는 `verifier`
- 외부 Gemini 리뷰를 쓰는 경우에도 로컬 증거를 먼저 만들고, Gemini는 최종 checker 역할로만 사용한다.
