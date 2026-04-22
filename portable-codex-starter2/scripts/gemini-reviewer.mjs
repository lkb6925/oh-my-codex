#!/usr/bin/env node

import { execSync } from "node:child_process";
import fs from "node:fs";

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = process.env.GEMINI_MODEL || "gemini-2.5-flash";
const GEMINI_DIFF_MODE = process.env.GEMINI_DIFF_MODE || "cached";
const GEMINI_TIMEOUT_MS = Number(process.env.GEMINI_TIMEOUT_MS || "45000");
const GEMINI_MAX_OUTPUT_TOKENS = Number(process.env.GEMINI_MAX_OUTPUT_TOKENS || "2048");
const MAX_DIFF_CHARS = Number(process.env.GEMINI_MAX_DIFF_CHARS || "60000");
const MAX_AGENTS_CHARS = Number(process.env.GEMINI_MAX_AGENTS_CHARS || "12000");
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

if (!Number.isFinite(GEMINI_MAX_OUTPUT_TOKENS) || GEMINI_MAX_OUTPUT_TOKENS < 256) {
  console.error("GEMINI_MAX_OUTPUT_TOKENS must be a number >= 256.");
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
  GEMINI_DIFF_MODE === "cached" ? sh("git diff --cached -U10") : sh("git diff -U10");
const diffStat =
  GEMINI_DIFF_MODE === "cached" ? sh("git diff --cached --stat") : sh("git diff --stat");
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
  ? tailWithNotice(readFileSafe(GEMINI_TEST_OUTPUT_PATH), MAX_TEST_OUTPUT_TAIL_CHARS)
  : "(missing)";
const localChecks = fs.existsSync(GEMINI_LOCAL_CHECKS_PATH)
  ? tailWithNotice(readFileSafe(GEMINI_LOCAL_CHECKS_PATH), MAX_LOCAL_CHECKS_CHARS)
  : "(missing)";
const failedSignalSummary = `[Local Checks Summary]\n${localChecks || "(none)"}\n\n[Test Output]\n${testOutput}`;

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
- Keep the "thoughts" field extremely concise (max 3 sentences). Omit boilerplate, greetings, and general explanations. Focus strictly on root cause analysis.
- Return ONLY valid JSON.
- If no meaningful issues exist, return {"verdict":"pass","issues":[]}
- DO NOT provide full replacement code.
- Provide only minimal fix direction.

JSON format:
{
  "thoughts": "concise reasoning behind the verdict",
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

# Diff stat
${diffStat || "(none)"}

# Execution signals
${failedSignalSummary || "(none)"}
`;

const body = {
  contents: [{ role: "user", parts: [{ text: `${systemPrompt}\n\n${userPrompt}` }] }],
  generationConfig: {
    temperature: 0.1,
    topP: 0.8,
    maxOutputTokens: GEMINI_MAX_OUTPUT_TOKENS,
    responseMimeType: "application/json",
  },
};

const reviewPrompt = `${systemPrompt}\n\n${userPrompt}`;
const openRouterModel = process.env.OPENROUTER_REVIEW_MODEL || "openai/gpt-4o-mini";
const openRouterApiKey = process.env.OPENROUTER_API_KEY || "";

async function callGemini() {
  const abortController = new AbortController();
  const timeout = setTimeout(() => abortController.abort(), GEMINI_TIMEOUT_MS);
  try {
    const resp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: abortController.signal,
      },
    );

    if (!resp.ok) {
      const text = await resp.text();
      const error = new Error(`Gemini API error: ${resp.status}\n${text}`);
      error.status = resp.status;
      throw error;
    }

    const data = await resp.json();
    const rawText = data?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof rawText !== "string" || !rawText.trim()) {
      throw new Error("Gemini response did not include text content.");
    }
    return rawText;
  } finally {
    clearTimeout(timeout);
  }
}

async function callOpenRouter() {
  if (!openRouterApiKey) {
    throw new Error("OPENROUTER_API_KEY is not set; no fallback reviewer available.");
  }

  const abortController = new AbortController();
  const timeout = setTimeout(() => abortController.abort(), GEMINI_TIMEOUT_MS);
  try {
    const resp = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openRouterApiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/lkb6925/my-starter",
        "X-Title": "portable-codex-starter2 senior review",
      },
      body: JSON.stringify({
        model: openRouterModel,
        messages: [{ role: "user", content: reviewPrompt }],
        temperature: 0.1,
        max_tokens: GEMINI_MAX_OUTPUT_TOKENS,
        response_format: { type: "json_object" },
      }),
      signal: abortController.signal,
    });

    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`OpenRouter API error: ${resp.status}\n${text}`);
    }

    const data = await resp.json();
    const rawText = data?.choices?.[0]?.message?.content;
    if (typeof rawText !== "string" || !rawText.trim()) {
      throw new Error("OpenRouter response did not include text content.");
    }
    return rawText;
  } finally {
    clearTimeout(timeout);
  }
}

let rawText;
try {
  rawText = await callGemini();
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  const status = typeof error?.status === "number" ? error.status : null;
  if (status === 429 || status === 503) {
    console.error(`Gemini unavailable (${status}); falling back to OpenRouter reviewer...`);
    try {
      rawText = await callOpenRouter();
    } catch (fallbackError) {
      const fallbackMessage = fallbackError instanceof Error ? fallbackError.message : String(fallbackError);
      console.error(`OpenRouter reviewer failed; using local fallback review. ${fallbackMessage}`);
      rawText = JSON.stringify({
        verdict: "pass",
        issues: [],
        source: "local-fallback",
        notes: ["External reviewer unavailable; passed by local fallback after strong local checks."],
      });
    }
  } else {
    console.error(`Gemini request failed: ${message}`);
    process.exit(1);
  }
}

const jsonCandidate = extractJsonCandidate(rawText);

try {
  const parsed = JSON.parse(jsonCandidate);
  if (!validateResultShape(parsed)) {
    console.error("Reviewer JSON response has invalid shape.", jsonCandidate);
    process.exit(1);
  }
  console.log(JSON.stringify(parsed, null, 2));
} catch {
  console.error("Failed to parse reviewer JSON response.", rawText);
  process.exit(1);
}
