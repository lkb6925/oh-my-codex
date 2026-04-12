# Portable Codex Starter 2

이 폴더는 낮용 Codespaces + Codex starter다.

역할은 단순하다.

- 낮: Codespaces 안에서 Codex로 정밀 수정, UI/UX 다듬기, 가벼운 버그 수정
- 밤: OMX + Hermes가 VM에서 무거운 구현, 대량 시도, 자동화 처리

즉 이 starter는 의도적으로 가볍다.
OMX와 겹치는 자동화는 넣지 않았다.

## 핵심만

- `AGENTS.md`로 Codex 작업 태도 고정
- `.codex/agents/`에 핵심 4인방만 유지
- `.agents/skills/`로 반복 절차 고정
- `.devcontainer/`로 Codespaces 기본 환경 준비
- `.codex/config.toml`로 MCP 기본값 제공

넣지 않은 것:

- Gemini checker 루프
- pre-push gate
- GitHub/Copilot instruction/hook/workflow 계층
- 야간 공장형 자동화
- OMX runtime 대체물

## 가장 빠른 시작

이 폴더 안에서:

```bash
node scripts/install.mjs --target /path/to/your-project --with-config
node scripts/doctor.mjs --target /path/to/your-project
```

Codex core만 넣고 싶으면:

```bash
node scripts/install.mjs --target /path/to/your-project --with-config --core-only
node scripts/doctor.mjs --target /path/to/your-project --core-only
```

skills를 `.codex/skills/`에 넣고 싶으면:

```bash
node scripts/install.mjs --target /path/to/your-project --with-config --skills-root=.codex
node scripts/doctor.mjs --target /path/to/your-project --skills-root=.codex
```

## 설치되면 들어가는 것

풀세트 기준:

- `AGENTS.md`
- `.codex/agents/`
- `.agents/skills/`
- `.codex/config.toml`
- `.codex/config.toml.example`
- `.codex/mcp-servers.example.toml`
- `.codex/starter-docs/`
- `.devcontainer/`

## 지금 들어 있는 Codex 역할

기본 역할은 딱 4개만 남긴다.

- 계획: `planner`
- 구조 설계: `architect`
- 구현: `executor`
- 문제 해결: `debugger`

## Codex에게 이렇게 말하면 된다

- `planner로 이 작업 계획만 세워줘. 아직 구현하지 마.`
- `architect 관점으로 현재 구조의 리스크를 분석해줘.`
- `executor처럼 바로 구현하고 테스트까지 해줘.`
- `debugger로 이 에러 원인부터 잡아줘.`

## 이 starter가 맡는 범위

- 낮 시간대 인터랙티브 작업
- 디테일 수정
- 구조 이해
- 로컬 테스트와 검증
- MCP 기반 사실 확인

## 이 starter가 맡지 않는 범위

- 장시간 자동 수정 루프
- 푸시 차단 게이트
- Gemini checker
- GitHub cloud automation
- OMX 팀 런타임 대체

그건 VM의 OMX + Hermes가 맡는다.

## 추천 사용 흐름

1. 새 repo를 Codespaces로 연다.
2. 이 starter를 설치한다.
3. `doctor`로 확인한다.
4. 낮 동안 Codex로 정밀 수정한다.
5. 작업이 끝나면 반드시 commit/push 한다.
6. 밤에는 VM의 OMX가 그 브랜치를 pull 해서 이어서 작업한다.

## 현재 기준 검증 포인트

- `.codex/agents` 4개
- `.agents/skills` 존재
- `.devcontainer` 존재
- `.codex/config.toml` 존재

## 기본 MCP와 추가 추천

이 starter를 설치하면 아래 2개는 기본으로 들어간다.

- `openaiDeveloperDocs`
- `context7`

`context7`를 더 안정적으로 쓰려면 `CONTEXT7_API_KEY`를 Codespaces secret으로 넣는 것을 권장한다.

세 번째 추천은 작업 성격에 따라 고르면 된다.

- 프론트엔드/브라우저 디버깅이 많다: `chrome_devtools`
- 문서/파일 변환이 많다: `markitdown`
- API 계약 중심 개발이 많다: `OpenAPI`
- DB 스키마/쿼리 검증이 많다: `Postgres MCP`

GitHub 작업은 별도 GitHub MCP보다 GitHub plugin/connector를 우선하는 쪽을 권장한다.

`Postgres MCP`는 읽기 전용 참고 도구로 쓰는 것이 기본이다.
즉, 스키마 확인과 migration 코드 생성까지는 가능하지만, DB에 직접 쓰기 작업을 하는 기본 워크플로우는 켜두지 않았다.

## 더 긴 설명

- 운영 가이드: [docs/automation-playbook.md](docs/automation-playbook.md)
- MCP 설정: [docs/mcp-setup.md](docs/mcp-setup.md)
- 소스 맵: [docs/source-map.md](docs/source-map.md)
