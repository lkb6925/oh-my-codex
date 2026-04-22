---
name: postgres-readonly
description: Inspect the live Postgres schema safely without mutating data
---

# Postgres Readonly

Use this skill when you need the real database schema as evidence before writing code, queries, repositories, or migrations.

## Use when

- checking whether code matches the live schema
- confirming tables, columns, types, nullability, indexes, constraints, enums, or foreign keys
- reviewing migration impact before generating a migration
- verifying query assumptions before writing SQL or repository code

## Workflow

1. Treat `Postgres MCP` as a read-only schema source of truth.
2. Prefer dev or staging over production.
3. Inspect schema shape first: tables, columns, types, constraints, indexes, foreign keys, enums.
4. Compare code assumptions against the live schema.
5. Report any mismatch explicitly.
6. If a schema change is needed, stop inspection and hand off to a migration-generation workflow instead of mutating through MCP.

## Allowed

- inspect tables
- inspect columns and types
- inspect nullability
- inspect indexes and constraints
- inspect foreign keys and enums
- inspect migration impact

## Forbidden

- `INSERT`
- `UPDATE`
- `DELETE`
- `DROP`
- `TRUNCATE`
- `ALTER`
- any destructive or mutating SQL

## Production rule

- If the connected database is production, do not perform any write action even if asked casually.
- Use production only as read-only and only when necessary.
- Prefer schema inspection over reading real rows.

## Output

- schema facts confirmed
- code/schema mismatches
- migration needed or not
- risks or unknowns
