#!/usr/bin/env node

import { execSync } from "node:child_process";
import fs from "node:fs";

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = process.env.GEMINI_MODEL || "gemini-2.5-pro";
const GEMINI_DIFF_MODE = process.env.GEMINI_DIFF_MODE || "cached";
const GEMINI_TIMEOUT_MS = Number(process.env.GEMINI_TIMEOUT_MS || "45000");
const MAX_DIFF_CHARS = Number(process.env.GEMINI_MAX_DIFF_CHARS || "120000");
const MAX_AGENTS_CHARS = Number(process.env.GEMINI_MAX_AGENTS_CHARS || "12000");
const MAX_TEST_OUTPUT_CHARS = Number(process.env.GEMINI_MAX_TEST_OUTPUT_CHARS || "20000");
const MAX_TEST_OUTPUT_TAIL_CHARS = Number(process.env.GEMINI_MAX_TEST_OUTPUT_TAIL_CHARS || "10000");
const GEMINI_TEST_OUTPUT_PATH = process.env.GEMINI_TEST_OUTPUT_PATH || ".tmp-test-output.txt";
const GEMINI_LOCAL_CHECKS_PATH = process.env.GEMINI_LOCAL_CHECKS_PATH || ".tmp-local-checks-round1.log";
const MAX_LOCAL_CHECKS_CHARS = Number(process.env.GEMINI_MAX_LOCAL_CHECKS_CHARS || "12000");

if (!GEMINI_API_KEY) {
  console.error("GEMINI_API_KEY is not set. Please export it.");
  process.exit(1);
}

if (!Number.isFinite(GEMINI_TIMEOUT_MS) || GEMINI_TIMEOUT_MS < 1000) {
  console.error("GEMINI_TIMEOUT_MS must be a number >= 1000.");
  process.exit(1);
}

function sh(cmd) {
  try {
    return execSync(cmd, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
  } catch {
    return "";
  }
}

function getChangedFiles() {
  const out =
    GEMINI_DIFF_MODE === "cached"
      ? sh("git diff --cached --name-only")
      : sh("git diff --name-only");
  return out ? out.split("\n").filter(Boolean) : [];
}

function readFileSafe(path) {
  try {
    return fs.readFileSync(path, "utf8");
  } catch {
    return "";
  }
}

function truncateWithNotice(value, maxChars) {
  if (value.length <= maxChars) {
    return value;
  }

  const omitted = value.length - maxChars;
  return `${value.slice(0, maxChars)}\n\n...[truncated ${omitted} chars]`;
}

function tailWithNotice(value, maxChars) {
  if (value.length <= maxChars) {
    return value;
  }

  const omitted = value.length - maxChars;
  return `...[truncated ${omitted} chars from start]\n\n${value.slice(-maxChars)}`;
}

function extractJsonCandidate(value) {
  const trimmed = value.trim();
  if (!trimmed) {
    return "";
  }

  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  if (fenced?.[1]) {
    return fenced[1].trim();
  }

  return trimmed;
}

function validateResultShape(parsed) {
  if (typeof parsed !== "object" || parsed === null) {
    return false;
  }

  if (parsed.verdict !== "pass" && parsed.verdict !== "fail") {
    return false;
  }

  if (!Array.isArray(parsed.issues)) {
    return false;
  }

  for (const issue of parsed.issues) {
    if (typeof issue !== "object" || issue === null) {
      return false;
    }
    if (typeof issue.blocking !== "boolean") {
      return false;
    }
    if (typeof issue.policy_violation !== "boolean") {
      return false;
    }
  }

  return true;
}

const diff =
  GEMINI_DIFF_MODE === "cached" ? sh("git diff --cached") : sh("git diff");
const changedFiles = getChangedFiles();
const workingTreeDiff = sh("git diff --name-only");

if (!diff.trim()) {
  if (GEMINI_DIFF_MODE === "cached" && workingTreeDiff.trim()) {
    console.error(
      "No staged diff found for review. Stage your changes first (e.g., `git add .`) before running senior-review.",
    );
    process.exit(1);
  }
  console.log(JSON.stringify({ verdict: "pass", issues: [] }, null, 2));
  process.exit(0);
}

const agentsMd = fs.existsSync("AGENTS.md")
  ? truncateWithNotice(readFileSafe("AGENTS.md"), MAX_AGENTS_CHARS)
  : "";
const testOutput = fs.existsSync(GEMINI_TEST_OUTPUT_PATH)
  ? tailWithNotice(
      truncateWithNotice(readFileSafe(GEMINI_TEST_OUTPUT_PATH), MAX_TEST_OUTPUT_CHARS),
      MAX_TEST_OUTPUT_TAIL_CHARS,
    )
  : "(missing)";
const localChecks = fs.existsSync(GEMINI_LOCAL_CHECKS_PATH)
  ? truncateWithNotice(readFileSafe(GEMINI_LOCAL_CHECKS_PATH), MAX_LOCAL_CHECKS_CHARS)
  : "(missing)";
const filteredLocalChecks = localChecks
  .split("\n")
  .filter((line) => /\[FAIL\]|\[ERROR\]|\[SKIP\]|^=== summary ===|^(lint|typecheck|test|build)=/.test(line))
  .slice(0, 120)
  .join("\n");
const failedSignalSummary = `[Local Checks Summary]\n${filteredLocalChecks || "(none)"}\n\n[Test Output]\n${testOutput}`;

const systemPrompt = `
You are a brutally strict senior software architect with 15 years of experience reviewing production systems.
Review the provided code changes. Focus only on:
1. algorithm design and time/space complexity
2. architectural weaknesses
3. missing edge cases and exception handling
4. missing functionality implied by the implementation
5. maintainability risks
6. security/data-model guardrails for auth and persistence (password hashing, unique indexes, PK strategy)

Rules:
- Never praise. Only report things that should be fixed.
- Be specific and harsh, but technically correct.
- Return ONLY valid JSON.
- If no meaningful issues exist, return {"verdict":"pass","issues":[]}
- DO NOT provide full replacement code.
- Provide only minimal fix direction.

JSON format:
{
  "verdict": "pass" | "fail",
  "issues": [
    {
      "severity": "critical" | "high" | "medium" | "low",
      "category": "correctness" | "performance" | "architecture" | "edge-case",
      "file": "path/to/file",
      "reason": "why this is a problem",
      "fix": "specific minimal fix direction",
      "blocking": true | false,
      "policy_violation": true | false
    }
  ]
}
`;

const userPrompt = `
# Context (AGENTS.md)
${agentsMd || "(none)"}

# Changed files
${JSON.stringify(changedFiles, null, 2)}

# Diff
${truncateWithNotice(diff, MAX_DIFF_CHARS)}

# Test output
${testOutput}

# Local checks output
${localChecks}

# Failed signal summary
${failedSignalSummary || "(none)"}
`;

const body = {
  contents: [{ role: "user", parts: [{ text: `${systemPrompt}\n\n${userPrompt}` }] }],
  generationConfig: { temperature: 0.1, topP: 0.8, responseMimeType: "application/json" },
};

const abortController = new AbortController();
const timeout = setTimeout(() => abortController.abort(), GEMINI_TIMEOUT_MS);

let resp;
try {
  resp = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: abortController.signal,
    }
  );
} catch (error) {
  clearTimeout(timeout);
  const message = error instanceof Error ? error.message : String(error);
  console.error(`Gemini request failed: ${message}`);
  process.exit(1);
}

clearTimeout(timeout);

if (!resp.ok) {
  const text = await resp.text();
  console.error(`Gemini API error: ${resp.status}\n${text}`);
  process.exit(1);
}

const data = await resp.json();
const rawText = data?.candidates?.[0]?.content?.parts?.[0]?.text;

if (typeof rawText !== "string" || !rawText.trim()) {
  console.error("Gemini response did not include text content.");
  process.exit(1);
}

const jsonCandidate = extractJsonCandidate(rawText);

try {
  const parsed = JSON.parse(jsonCandidate);
  if (!validateResultShape(parsed)) {
    console.error("Gemini JSON response has invalid shape.", jsonCandidate);
    process.exit(1);
  }
  console.log(JSON.stringify(parsed, null, 2));
} catch {
  console.error("Failed to parse Gemini JSON response.", rawText);
  process.exit(1);
}
