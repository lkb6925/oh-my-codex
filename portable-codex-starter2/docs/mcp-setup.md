# MCP Setup Guide

이 문서는 `starter2`를 VM 하네스로 쓸 때 필요한 MCP만 남겨 두는 기준 문서다.

## 기본 원칙

- 기본 MCP는 `context7`, `postgres` 두 개뿐이다.
- 프레임워크나 라이브러리 지식은 `context7`로 해결한다.
- 실제 DB 스키마 확인은 `postgres`로 해결한다.
- 그 외 MCP는 기본값에서 제외한다.
- 인터넷 검색은 마지막 수단으로만 사용한다.

## 기본 설정

starter의 기본 `.codex/config.toml`에는 아래 두 MCP만 들어 있다.

```toml
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp"]

[mcp_servers.postgres]
command = "bash"
args = ["scripts/postgres-mcp.sh"]
```

## 운영 규칙

- Next.js, React, 일반 라이브러리 문제: 먼저 `context7`
- DB 컬럼, 제약, enum, migration 영향 확인: 먼저 `postgres`
- 코드와 실제 DB가 다르면 추측하지 말고 차이를 명시한다
- `postgres`는 기본적으로 읽기 전용 스키마 점검 도구로 취급한다
- production 연결이어도 직접 write/DDL은 하지 않는다

## VM 실행 전 체크리스트

1. `POSTGRES_MCP_DSN`을 VM secret/environment에 주입한다. (Git에 평문 저장 금지)
2. 가능하면 `sslmode=require`를 사용한다.
3. 권한 검증 SQL로 write/DDL 권한이 없는 계정인지 확인한다.
4. `bash scripts/vm-ready-check.sh`로 VM 사전 점검을 통과한다.
5. 실제 리뷰 실행은 `STRICT_LOCAL_CHECKS=1 bash scripts/get-senior-review.sh 1`로 시작한다.
6. local verification만 따로 돌릴 때는 `bash scripts/run-local-checks.sh`를 사용한다.

### 참고: 로컬 포장/배포 준비 중일 때

- `GEMINI_API_KEY`는 VM 셸 환경이나 `~/.hermes/.env`에서 읽어온다. 따라서 VM에 이미 키를 넣어두었다면 `scripts/vm-ready-check.sh`와 senior review가 그대로 그 값을 쓸 수 있다.
- `HERMES_ENV_FILE`를 따로 지정하면 `~/.hermes/.env` 대신 그 파일을 사용한다.
- DSN은 파일 치환 대신 `POSTGRES_MCP_DSN` 환경 변수로만 주입한다.
- 위 두 항목까지 실패로 강제하려면 아래처럼 strict 모드를 사용한다.

```bash
VM_PREFLIGHT_STRICT=1 bash scripts/vm-ready-check.sh
```

### 환경변수 지속성(.env)

- `scripts/postgres-mcp.sh`, `scripts/vm-ready-check.sh`, `scripts/get-senior-review.sh`는 `ENV_FILE` 지정이 있으면 그 파일을 우선 로드하고, 없으면 `.env.local` → `.env` 순서로 로드한다.
- tmux/새 셸에서도 같은 값을 유지하려면 VM 프로젝트 루트 `.env`를 사용한다.
- CI/프로덕션에서는 `REQUIRE_EXPLICIT_ENV_FILE=1`(또는 `CI=true`)로 실행해 `ENV_FILE` 미지정 시 즉시 실패하도록 설정한다.

## Context7

용도:

- 프레임워크와 라이브러리 문서 확인
- 최신 권장 사용법 확인
- 검색량 절감

권장:

- `CONTEXT7_API_KEY`를 환경 변수나 secret으로 설정

확인:

```bash
node scripts/doctor.mjs --target /path/to/your-project
```

## Postgres

용도:

- 실제 스키마 확인
- 존재하지 않는 컬럼/테이블 추정 방지
- migration 영향 확인

주의:

- 연결 문자열은 프로젝트에 맞게 바꿔야 한다
- 연결 문자열은 Git에 저장하지 말고 환경 변수로만 주입한다
- 스키마 조회 전용이면 read-only 계정을 우선한다
- 마이그레이션 생성/검증이 필요하면 MCP DSN과 앱 실행 DSN을 분리해 관리한다

### Supabase 운영 기준

- Supabase를 쓰면 VM에 `POSTGRES_MCP_DSN`을 secret으로 넣고 `scripts/postgres-mcp.sh`가 그 값을 사용한다.
- 앱 실행용 DB URL(`DATABASE_URL` 등)과 MCP 점검용 DSN(`POSTGRES_MCP_DSN`)은 분리한다.
- Git tracked 파일에는 Supabase 비밀번호가 포함된 DSN을 절대 저장하지 않는다.

## Senior Review 증거 기준

- `typecheck`는 반드시 pass여야 한다.
- `test`가 pass면 가장 좋다.
- `test`가 없거나 실패하면 `build` pass를 대체 증거로 허용한다.
- 테스트를 설정할 때는 watch 모드가 아닌 1회 실행 모드(`vitest run`, `jest --passWithNoTests`)를 사용한다.
- 위 조건은 `STRICT_LOCAL_CHECKS=1`에서 강제되고, non-strict 모드에서는 경고로만 기록된다.
- strict에서 `test`를 생략하려면 `ALLOW_BUILD_ONLY_REVIEW=1`을 명시적으로 설정해야 한다(임시 면책).

## 추천 설치 방식

VM 하네스로는 보통 아래 조합이 가장 안전하다.

```bash
node scripts/install.mjs --target /path/to/your-project --with-config --core-only
node scripts/doctor.mjs --target /path/to/your-project
```
