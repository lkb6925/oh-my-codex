#!/usr/bin/env node

import fs from "node:fs";

const args = process.argv.slice(2);
const fileFlagIndex = args.indexOf("--file");
const isFinal = args.includes("--final");
const reviewPath =
  fileFlagIndex >= 0 && args[fileFlagIndex + 1] ? args[fileFlagIndex + 1] : ".tmp-gemini-review.json";

if (!fs.existsSync(reviewPath)) {
  console.error(`[ERROR] Review file not found: ${reviewPath}`);
  process.exit(1);
}

let parsed;
try {
  parsed = JSON.parse(fs.readFileSync(reviewPath, "utf8"));
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`[ERROR] Failed to parse review JSON: ${message}`);
  process.exit(1);
}

if (!parsed || !Array.isArray(parsed.issues)) {
  console.error("[ERROR] Invalid review shape: missing issues array.");
  process.exit(1);
}

const issues = parsed.issues;
const criticalOrBlockingIssues = issues.filter(
  (issue) => issue?.severity === "critical" || issue?.blocking === true,
);
if (criticalOrBlockingIssues.length > 0) {
  console.error(
    `[ERROR] Blocking issues detected (${criticalOrBlockingIssues.length}). Do NOT commit until fixed.`,
  );
  process.exit(1);
}

if (isFinal) {
  const architectureOrAgentsIssues = issues.filter((issue) => issue?.policy_violation === true);

  if (architectureOrAgentsIssues.length > 0) {
    console.error(
      `[ERROR] Architecture/AGENTS violations remain (${architectureOrAgentsIssues.length}). Do NOT commit.`,
    );
    process.exit(1);
  }
}

console.log(`[PASS] Review gate passed for ${reviewPath}${isFinal ? " (final)" : ""}.`);
