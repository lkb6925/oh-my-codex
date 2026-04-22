# Source Map

이 파일은 `starter2`가 무엇을 남기고 무엇을 버렸는지 기록한다.

## 남긴 것

- `AGENTS.md`
  장기 실행용 Codex 작업 계약으로 유지
- `.codex/agents/architect.toml`
- `.codex/agents/planner.toml`
- `.codex/agents/executor.toml`
- `.codex/agents/debugger.toml`
  핵심 4인방만 유지
- `.agents/skills/*`
  repo 탐색, 리뷰, DB 점검, 정리용 portable skill 유지
- `.codex/config.toml`
  `context7`, `postgres` 기본값 유지
- `.omx/checkpoints/`
  장기 실행용 체크포인트 복구 지점 유지
- `.devcontainer/**`
  필요할 때만 쓰는 보조 계층으로 유지
- `scripts/install.mjs`
- `scripts/doctor.mjs`
- `scripts/lib/load-env.sh`
- `scripts/run-local-checks.sh`
- `scripts/factory-night.sh`
- `scripts/factory-status.sh`
- `scripts/factory-watch.sh`
- `scripts/factory-summary.sh`
- `scripts/factory-finish.sh`
- `scripts/factory-self-check.sh`

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

- 기존 Hermes / Codex CLI / OMX 런타임을 방해하지 않는다.
- 필요한 행동 강령과 최소 MCP만 덧씌운다.
- runtime에 꼭 필요한 파일만 남긴다.
- 복붙 후 바로 쓰기 쉬운 쪽을 우선한다.
- Hermes는 운영자 인터페이스를 소비하고, 실행은 Codex/OMX가 담당한다.
