# Source Map

이 파일은 `starter2`가 무엇을 남기고 무엇을 버렸는지 기록한다.

## 남긴 것

- `AGENTS.md`
  낮용 Codex 작업 계약으로 유지
- `.codex/agents/architect.toml`
- `.codex/agents/planner.toml`
- `.codex/agents/executor.toml`
- `.codex/agents/debugger.toml`
  핵심 4인방만 유지
- `.agents/skills/*`
  repo 탐색, 리뷰, DB 점검, 정리용 portable skill 유지
- `.codex/config.toml`
  MCP 기본값 유지
- `.devcontainer/**`
  Codespaces 부트스트랩 유지
- `scripts/install.mjs`
- `scripts/doctor.mjs`

## 뺀 것

- `.ai/**`
  Gemini checker loop는 제거
- `.githooks/**`
  pre-push gate 제거
- `.github/**`
  GitHub/Copilot instruction, hook, workflow, cloud agent 계층 제거
- `.codex/agents` 나머지 역할
  OMX와 겹치는 세부 역할 제거
- `prompts/**`
  source prompt와 generator 체인은 제거
- `scripts/generate-agents.mjs`
  런타임에 필요 없는 agent 재생성 계층 제거
- `scripts/verify.mjs`
- `scripts/verify-mcp-contract.mjs`
  무거운 검증 진입점 제거

## 설계 원칙

- 낮용 Codespaces + Codex만 담당한다.
- 밤용 자동화는 OMX/Hermes가 담당한다.
- runtime에 꼭 필요한 파일만 남긴다.
- 복붙 후 바로 쓰기 쉬운 쪽을 우선한다.
