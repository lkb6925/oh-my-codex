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

1. `POSTGRES_READONLY_URL`을 VM secret/environment에 주입한다. (Git에 평문 저장 금지)
2. 가능하면 `sslmode=require`를 사용한다.
3. 권한 검증 SQL로 write/DDL 권한이 없는 계정인지 확인한다.
4. `bash scripts/vm-ready-check.sh`로 VM 사전 점검을 통과한다.
5. 실제 리뷰 실행은 `STRICT_LOCAL_CHECKS=1 bash scripts/get-senior-review.sh`로 수행한다.

### 참고: 로컬 포장/배포 준비 중일 때

- `GEMINI_API_KEY`를 이미 VM에서 주입할 예정이면, 로컬에서 preflight 실행 시 경고만 보고 넘어가도 된다.
- DSN은 파일 치환 대신 `POSTGRES_READONLY_URL` 환경 변수로만 주입한다.
- 위 두 항목까지 실패로 강제하려면 아래처럼 strict 모드를 사용한다.

```bash
VM_PREFLIGHT_STRICT=1 bash scripts/vm-ready-check.sh
```

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
- 전용 read-only 계정을 써야 한다
- read-only 접근을 우선한다

## 추천 설치 방식

VM 하네스로는 보통 아래 조합이 가장 안전하다.

```bash
node scripts/install.mjs --target /path/to/your-project --with-config --core-only
node scripts/doctor.mjs --target /path/to/your-project
```
