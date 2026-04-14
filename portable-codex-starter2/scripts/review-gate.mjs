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
const criticalIssues = issues.filter((issue) => issue?.severity === "critical");
if (criticalIssues.length > 0) {
  console.error(
    `[ERROR] Blocking critical issues detected (${criticalIssues.length}). Do NOT commit until fixed.`,
  );
  process.exit(1);
}

if (isFinal) {
  const architectureOrAgentsIssues = issues.filter((issue) => {
    const category = typeof issue?.category === "string" ? issue.category.toLowerCase() : "";
    const reason = typeof issue?.reason === "string" ? issue.reason.toLowerCase() : "";
    const fix = typeof issue?.fix === "string" ? issue.fix.toLowerCase() : "";
    return (
      category === "architecture" ||
      reason.includes("agents.md") ||
      reason.includes("architectural inconsistency") ||
      fix.includes("agents.md") ||
      fix.includes("architectural inconsistency")
    );
  });

  if (architectureOrAgentsIssues.length > 0) {
    console.error(
      `[ERROR] Architecture/AGENTS violations remain (${architectureOrAgentsIssues.length}). Do NOT commit.`,
    );
    process.exit(1);
  }
}

console.log(`[PASS] Review gate passed for ${reviewPath}${isFinal ? " (final)" : ""}.`);
