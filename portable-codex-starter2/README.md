# Unified Track Starter

이 폴더는 OMX + Hermes + Codex CLI가 이미 깔린 환경에 덧씌우는 경량 하네스다.

핵심 목표는 단순하다.

- AGENTS 규칙과 4인방 에이전트를 제공한다.
- `context7`와 `postgres`만 기본 MCP로 둔다.
- `postgres`는 read-only 계정 기준으로만 사용한다.
- VM에서 밤새 돌아가도 기존 런타임을 방해하지 않게 유지한다.
- Hermes 없이도 단독으로 돌아가는 야간 공장 하네스를 제공한다.

## 핵심만

- `AGENTS.md`로 Codex 작업 태도 고정
- `.codex/agents/`에 핵심 4인방만 유지
- `.agents/skills/`로 반복 절차 고정
- `.omx/checkpoints/`로 체크포인트 복구 지점 제공
- `.omx/hooks/`와 `scripts/harness-event.mjs`로 run/event 기록
- 설치는 `.omx/checkpoints/`만 옮기고 `.omx/state`, `.omx/logs`, `.omx/runs`는 VM 로컬에 남긴다.
- `.devcontainer/`는 필요할 때만 쓰는 보조 파일
- `.codex/config.toml`로 MCP 기본값 제공

기본 철학:

- 하네스는 추가하되 기존 OMX/Hermes/Codex 런타임을 대체하지 않는다.
- cloud hook/workflow 계층은 넣지 않고 VM 로컬 운영 스크립트에 집중한다.
- 독립 작업은 병렬 worktree/worker 우선으로 처리하고, 파일이 겹칠 때만 직렬로 묶는다.
- 작업공간이 깨끗하면 `omx team`을 우선 고려한다. 팀 모드는 dedicated worktree를 자동으로 사용해 병렬 lane 관리에 유리하다.
- AGENTS/skills/system instructions are the already-loaded operating contract, not user memory; memory is only for user-specific stable preferences and environment facts.
- 한 줄 사용법: 낮엔 `factory`, 밤엔 `factory-night "할 일"`, 그리고 자면 된다.
- `factory`는 아침 브리핑 명령이다. 상태 + 요약을 한 번에 보여준다.
- `factory-night`는 밤 자동 실행 명령이다. 기본은 team lane이다.
- `factory-team`은 `factory-night`의 team 래퍼다. 밤의 병렬 lane 진입점으로 쓰고, 낮의 대화형 모드와는 분리한다.
- `factory:team`은 `omx team` 기반의 병렬 worktree lane 런처다. 작업공간이 깨끗할 때 우선 쓴다.
- `factory:team:shutdown`은 팀 세션을 종료하고 런타임 정리 상태를 남긴다.
## 역할 분리 (중요)

- **Codex CLI**: 실제 코드 작성/수정 실행자
- **OMX**: 장기 실행 런타임/워크플로우 계층
- **Gemini reviewer**: Gemini API key 기반 커밋 전 적대적 리뷰어
- **Hermes**: 상태/감시 스크립트를 읽는 외부 운영자(필수 아님)

## 가장 빠른 시작

VM이나 서버에 덮어쓸 때는 보통 이 경로가 가장 안전하다:

```bash
node scripts/install.mjs --target /path/to/your-project --with-config --core-only
node scripts/doctor.mjs --target /path/to/your-project
```

`.devcontainer/`까지 포함한 풀세트가 정말 필요할 때만:

```bash
node scripts/install.mjs --target /path/to/your-project --with-config
node scripts/doctor.mjs --target /path/to/your-project
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

- 장기 실행 하네스
- 구조 이해와 구현 지침
- 로컬 테스트와 검증
- MCP 기반 사실 확인
- VM handoff 친화적 체크포인트/커밋 흐름

## 이 starter가 맡지 않는 범위

- GitHub cloud automation/organization policy
- Hermes / OMX / Codex CLI 런타임 자체 대체
- 원격 CI/CD 파이프라인 자체 운영

위 범위는 기존 VM/원격 인프라 스택이 맡는다.

## 추천 사용 흐름

1. 새 repo 또는 작업 디렉터리를 준비한다.
2. 이 starter를 `--core-only`로 설치한다.
3. `doctor`로 확인한다.
4. OMX/Hermes가 밤새 이어받기 좋은 커밋 단위로 작업한다.
5. 작업이 끝나면 반드시 commit/push 한다.

## 야간 실행 빠른 시작

```bash
npm run vm:preflight
npm run factory
npm run factory:night
npm run factory:watch
npm run factory:summary
npm run factory:finish
npm run factory:status
```

운영 의미:
- `factory` = 아침 브리핑(상태 + 요약)
- `factory:night` = 실행 시작
- `factory:watch` = 감시/알림
- `factory:summary` = 현재 상태 요약
- `factory:finish` = 마감/푸시/전원 준비
- `factory:status` = 즉시 상태 조회

기본적으로 `factory:night`는 `FACTORY_COMMAND_POLICY=strict`로 실행되어 `OMX_COMMAND`를 보수적으로 검증한다. bare `omx`는 자동으로 `--tmux --madmax --high`를 붙여 실행하며, 위험 플래그 패턴은 차단된다.
장기적으로 더 구조화된 입력이 필요하면 `OMX_BIN` + `OMX_ARGS`를 사용할 수 있으며, 이 조합은 `OMX_COMMAND`보다 우선한다.
(`OMX_COMMAND`는 호환성 때문에 남아 있지만 deprecated 경고를 출력한다.)
`GEMINI_API_KEY`는 VM 셸 환경이나 `~/.hermes/.env`에서 읽어온다. senior review는 기본적으로 Gemini API key만 사용하며 `GEMINI_REVIEWER_BACKEND=api`가 기본값이다. `GOOGLE_API_KEY`나 `AI_API_KEY`가 들어 있어도 하네스가 같은 리뷰어 키로 정규화한다. 따라서 VM에 이미 키를 넣어두었다면 `npm run vm:preflight`와 senior review가 그대로 그 값을 쓸 수 있다.
완전 차단 모드가 필요하면 `FACTORY_REQUIRE_STRUCTURED_INPUT=1`을 설정하면 된다.

감시(읽기 전용):

```bash
npm run factory:watch
# 1회 체크만 하고 종료
bash scripts/factory-watch.sh --once
# 최대 10회 체크 후 종료
WATCH_MAX_CYCLES=10 bash scripts/factory-watch.sh
```

`factory-watch`는 `jq`를 우선 사용하고, `jq`가 없으면 `node` 파서로 fallback한다.
경고가 감지되면 `.omx/runs/latest-alert.json`에 최신 alert 스냅샷이 기록된다.

아침 요약:

```bash
npm run factory:summary
npm run factory:finish
npm run factory:self-check
```

## 현재 기준 검증 포인트

- `.codex/agents` 4개
- `.agents/skills` 존재
- `.omx/checkpoints` 존재
- `.codex/config.toml` 존재
- `.codex/config.toml` 안에 `context7`, `postgres` 존재

## 기본 MCP

이 starter를 설치하면 아래 2개만 기본으로 들어간다.

- `context7`
- `postgres`

`context7`를 더 안정적으로 쓰려면 `CONTEXT7_API_KEY`를 환경 변수나 secret으로 넣는 것을 권장한다.

`postgres`는 읽기 전용 참고 도구로 쓰는 것이 기본이다.
즉, 스키마 확인과 migration 코드 생성까지는 가능하지만, DB에 직접 쓰기 작업을 하는 기본 워크플로우는 켜두지 않았다.
실사용 전에는 `.codex/config.toml`의 DSN을 반드시 전용 read-only 계정으로 교체해야 한다.

## 더 긴 설명

- 운영 가이드: [docs/automation-playbook.md](docs/automation-playbook.md)
- MCP 설정: [docs/mcp-setup.md](docs/mcp-setup.md)
- 소스 맵: [docs/source-map.md](docs/source-map.md)
