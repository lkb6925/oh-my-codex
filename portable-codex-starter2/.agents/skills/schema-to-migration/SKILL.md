---
name: schema-to-migration
description: Inspect the live schema read-only, then generate migration code without mutating the database directly
---

# Schema To Migration

Use this skill when a task requires changing persisted data shape, but you want the database to stay read-only during planning and code generation.

## Use when

- code and schema disagree
- a new column, table, index, enum, or constraint is needed
- a migration file should be generated from verified schema facts
- you need to plan repository/query changes around a schema change

## Workflow

1. Use `Postgres MCP` only to inspect the current schema.
2. Confirm the exact current state before proposing any migration.
3. Compare the requested state against the live schema.
4. Generate migration code or migration files in the repository.
5. Update related code paths that depend on the schema shape.
6. Verify the generated migration against the inspected schema assumptions.
7. Never apply the migration through MCP as part of this workflow.

## Guardrails

- `Postgres MCP` is read-only here.
- Generate migration code; do not run destructive SQL through MCP.
- If the target database is production, refuse direct mutation and keep the workflow code-generation only.
- If row inspection is not strictly necessary, skip it.

## Recommended tool routing

- `Postgres MCP` for current schema truth
- local code inspection for repositories, models, and query callers
- migration tool or repo-local migration files for the actual change

## Output

- current schema facts
- requested schema delta
- generated migration files or code
- affected code paths
- verification and residual risks
