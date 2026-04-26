# Automation Playbook

이 문서는 `starter2`를 밤새 `tmux`에서 돌아가는 VM 하네스로 쓸 때의 운영 원칙을 정리한다.

## 목적

- Hermes, Codex CLI, OMX가 이미 설치된 환경에 덧씌운다
- 기존 런타임을 막지 않는다
- 최소 규칙만 추가한다
- handoff와 복구를 쉽게 만든다

## 운영 레이어 (overnight harness)

- `scripts/factory-night.sh`: 야간 실행 엔트리포인트 (tmux + OMX; 기본은 `omx exec` 기반의 무대화면 없는 작업 모드, `FACTORY_NIGHT_TASK`/`FACTORY_NIGHT_TASK_FILE`/인자 지원, 기본은 agent-only)
- `scripts/factory-status.sh`: 상태 확인(사람/기계 겸용, `--json` 지원)
- `scripts/factory-watch.sh`: 읽기 전용 감시/알림
- `scripts/factory-summary.sh`: 아침 점검용 요약 리포트 (`DONE` / `KEEP / PRUNE CANDIDATES` / `NEEDS YOUR DECISION` / `MACHINE / OPERATIONS`)
- `scripts/factory-finish.sh`: 최종 push/요약/종료 준비 상태 계산
- `scripts/factory-team.sh`: `omx team` 기반의 병렬 worktree lane 런처(깨끗한 repo일 때 우선 사용)
- `scripts/factory-team-status.sh`: team 상태 조회
- `scripts/factory-team-await.sh`: team 완료 대기
- `scripts/factory-team-summary.sh`: team 요약/상태 브리핑
- `scripts/factory-team-shutdown.sh`: team 종료/정리
- `scripts/factory-self-check.sh`: 상태/알림 JSON 계약 확인
- `scripts/run-local-checks.sh`: local verification 전용 분리 계층
- `scripts/harness-event.mjs`: watch/summary/finish용 이벤트 기록기

## 권장 설치

기본 권장:

```bash
node scripts/install.mjs --target /path/to/your-project --with-config --core-only
```

이 방식은 `.devcontainer/`를 복사하지 않으므로 VM 서버에 불필요한 Codespaces 흔적을 남기지 않는다.

## 포함 요소

- `AGENTS.md`
- `.codex/agents/`의 4인방
- `.agents/skills/`
- `.omx/checkpoints/`
- `.codex/config.toml`
- `scripts/install.mjs`
- `scripts/doctor.mjs`

## 실행 원칙

- 질문보다 진행을 우선한다
- 실패하면 `tail -n 100` 수준으로 로그를 먼저 읽는다
- 프레임워크 문서는 `context7`를 먼저 쓴다
- DB 스키마는 read-only `postgres`로 먼저 확인한다
- 의미 있는 마일스톤마다 git commit 또는 체크포인트를 남긴다
- Hermes는 감독자이며, 코드 실행자는 Codex CLI다

## 하지 않는 일

- push 차단 훅
- GitHub workflow 게이트
- Gemini checker 루프
- 자체 장기 재시도 런타임
- Hermes / OMX / Codex CLI 대체

## handoff 규칙

- 커밋 메시지에 바뀐 점, 남은 TODO, 다음 액션을 남긴다
- 아침에 이어받을 수 있도록 중간 상태를 재현 가능하게 남긴다
- DB 관련 작업은 실제 스키마와 코드 가정의 차이를 명시한다
- `postgres` DSN은 실사용 전에 반드시 read-only 계정으로 교체한다

## 기본 명령

```bash
# 야간 실행 시작 (idempotent)
bash scripts/factory-night.sh

# 병렬 worktree lane 시작 (clean repo 우선)
bash scripts/factory-team.sh --spec 4:executor "fix failing tests in parallel lanes"

# team 상태/요약/대기/종료
bash scripts/factory-team-status.sh
bash scripts/factory-team-summary.sh
bash scripts/factory-team-await.sh
bash scripts/factory-team-shutdown.sh

# 상태 확인
bash scripts/factory-status.sh
bash scripts/factory-status.sh --json

# 감시 (읽기 전용)
bash scripts/factory-watch.sh
bash scripts/factory-watch.sh --once

# 요약
bash scripts/factory-summary.sh

# 마감 처리 (push + final summary + poweroff 준비 계산 + team shutdown)
bash scripts/factory-finish.sh

# 하네스 계약 확인
bash scripts/factory-self-check.sh
```

`watch`는 스트림 감시, `summary`는 요약 브리핑, `finish`는 마감/푸시/세션 정리/팀 종료를 담당한다.

## 상태 JSON 스키마 (Hermes용)

`bash scripts/factory-status.sh --json`은 안정된 키를 제공한다.

- `schema_version`
- `generated_at`
- `run_state` (`running` | `idle` | `stalled` | `completed` | `failed`)
- `session_name`
- `session_exists`
- `branch`
- `dirty`
- `latest_commit`
- `latest_log`
- `log_age_seconds`
- `meta_file`
- `meta_age_seconds`
- `omx_status`
- `push_state`
- `last_review_verdict`
- `last_alert_file`
- `last_alert_severity`
- `last_alert_code`
- `poweroff_ready`
- `require_review_for_poweroff`
- `remaining_manual_actions`
- `execution_mode` (`tmux` | `omx-team` | `fallback`)
- `team_spec`
- `team_name`

타입 규칙:
- `session_exists`: boolean
- `dirty`: boolean (`true` = 변경사항 존재)
- `log_age_seconds`: number | null
- `meta_age_seconds`: number | null

## 운영 주의

- `run-local-checks.sh`는 `.harness.lock`(또는 `.harness.lock.d`)로 동시 실행을 차단한다.
- 기본 lock 모드는 `HARNESS_LOCK_MODE=mkdir`이며 NFS 친화적인 디렉터리 lock을 우선 사용한다. (`auto`/`flock`도 선택 가능)
- `factory-watch.sh`는 `jq`를 우선 사용하고, 없으면 `node` JSON 파서 fallback을 사용한다.
- `factory-watch.sh --once`로 1회 체크 후 종료할 수 있다.
- `WATCH_MAX_CYCLES=<n>`을 주면 무한 루프 대신 n회 체크 후 종료한다.
- alert 발생 시 `${FACTORY_RUN_DIR:-.omx/runs}/latest-alert.json` 스냅샷이 갱신되어 Hermes가 최신 경고 상태를 쉽게 소비할 수 있다.
- `.env` 로딩은 기본적으로 기존 shell env를 보존한다. 필요한 경우에만 `CODEX_ENV_OVERRIDE=1`로 덮어쓴다.
- `REQUIRE_REVIEW_FOR_POWEROFF` 기본값은 `0`이다. 리뷰 미실행(`unknown`)을 즉시 전원 차단 금지로 보려면 `REQUIRE_REVIEW_FOR_POWEROFF=1`을 명시한다.
- `factory-night.sh`는 기본 `strict` 정책에서 `OMX_COMMAND`를 보수적으로 검증한다.
  - `omx` 단독 입력은 자동으로 `--tmux --madmax --high`가 붙는다.
  - `--no-tmux`는 차단되고, `--tmux` 누락 시 자동 추가된다.
  - `--unsafe`, `--danger`, `--destructive`, `--no-sandbox` 패턴은 차단된다.
  - 비-`omx` 명령을 의도적으로 허용하려면 `FACTORY_ALLOW_NON_OMX_COMMAND=1`을 설정한다.
  - 정책을 완화하려면 `FACTORY_COMMAND_POLICY=permissive`를 명시한다.
- `factory-night.sh`는 기본 backend가 `omx team`이다. `FACTORY_NIGHT_TASK`/`FACTORY_NIGHT_TASK_FILE`/인자를 지원하며, 필요할 때만 `FACTORY_NIGHT_EXEC_MODE=exec`로 직접 exec 경로를 쓴다.
- `FACTORY_REQUIRE_STRUCTURED_INPUT=1`을 주면 `OMX_COMMAND` 경로를 막고 구조화 입력만 허용한다.
- `factory-team.sh`는 `omx team`을 실행해 dedicated worktree 기반 병렬 lane을 띄운다.
  - 기본 `4:executor` 스펙을 사용한다.
  - `FACTORY_TEAM_TASK` 또는 인자로 작업 지시를 넣어야 한다.
- 런 로그(`run-*.log`), 감시 로그(`watch-*.log`), launch 스크립트(`launch-*.sh`)는 7일 초과 시 정리된다.
