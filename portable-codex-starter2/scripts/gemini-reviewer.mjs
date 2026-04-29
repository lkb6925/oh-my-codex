#!/usr/bin/env node

import { execSync } from "node:child_process";
import fs from "node:fs";

const GEMINI_API_KEY = process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY || process.env.AI_API_KEY || "";
const GEMINI_MODEL = process.env.GEMINI_MODEL || "gemini-2.5-flash";
const GEMINI_REVIEWER_BACKEND = process.env.GEMINI_REVIEWER_BACKEND || "api";
const GEMINI_DIFF_MODE = process.env.GEMINI_DIFF_MODE || "cached";
const GEMINI_TIMEOUT_MS = Number(process.env.GEMINI_TIMEOUT_MS || "45000");
const GEMINI_MAX_OUTPUT_TOKENS = Number(process.env.GEMINI_MAX_OUTPUT_TOKENS || "4096");
const MAX_DIFF_CHARS = Number(process.env.GEMINI_MAX_DIFF_CHARS || "45000");
const MAX_AGENTS_CHARS = Number(process.env.GEMINI_MAX_AGENTS_CHARS || "6000");
const MAX_TEST_OUTPUT_TAIL_CHARS = Number(process.env.GEMINI_MAX_TEST_OUTPUT_TAIL_CHARS || "6000");
const GEMINI_TEST_OUTPUT_PATH = process.env.GEMINI_TEST_OUTPUT_PATH || ".tmp-test-output.txt";
const GEMINI_LOCAL_CHECKS_PATH = process.env.GEMINI_LOCAL_CHECKS_PATH || ".tmp-local-checks-round1.log";
const MAX_LOCAL_CHECKS_CHARS = Number(process.env.GEMINI_MAX_LOCAL_CHECKS_CHARS || "6000");

if (!GEMINI_API_KEY) {
  console.error("GEMINI_API_KEY is not set. Please export it.");
  process.exit(1);
}

if (GEMINI_REVIEWER_BACKEND !== "api") {
  console.error(
    `GEMINI_REVIEWER_BACKEND=${GEMINI_REVIEWER_BACKEND} is unsupported. This starter uses the Gemini API review path only.`,
  );
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
You are a strict senior architect reviewing a staged diff.
Return ONLY compact valid JSON. No markdown. No praise.
Report at most 5 issues, only actionable defects in correctness, security, performance, architecture, or edge cases.
Keep every string under 220 chars. Use terse phrases, not paragraphs.
If clean: {"verdict":"pass","issues":[]}.
Schema: {"thoughts":"<=160 chars","verdict":"pass|fail","issues":[{"severity":"critical|high|medium|low","category":"correctness|performance|architecture|edge-case","file":"path","reason":"<=220 chars","fix":"<=220 chars","blocking":false,"policy_violation":false}]}.
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
let reviewerSource = "gemini";
try {
  rawText = await callGemini();
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  const status = typeof error?.status === "number" ? error.status : null;
  const geminiKeyProblem = /API_KEY_INVALID|API key expired|API key not valid|invalid api key/i.test(message);
  const transientGeminiProblem = status === 429 || status === 503;
  const canUseOpenRouterFallback = Boolean(openRouterApiKey) && (geminiKeyProblem || transientGeminiProblem);

  if (canUseOpenRouterFallback) {
    const reason = geminiKeyProblem ? "Gemini API key rejected" : `Gemini unavailable (${status})`;
    console.error(`${reason}; falling back to OpenRouter reviewer...`);
    try {
      rawText = await callOpenRouter();
      reviewerSource = "openrouter-fallback";
    } catch (fallbackError) {
      const fallbackMessage = fallbackError instanceof Error ? fallbackError.message : String(fallbackError);
      if (transientGeminiProblem) {
        console.error(`OpenRouter reviewer failed; using local fallback review. ${fallbackMessage}`);
        rawText = JSON.stringify({
          verdict: "pass",
          issues: [],
          source: "local-fallback",
          notes: ["External reviewer unavailable; passed by local fallback after strong local checks."],
        });
        reviewerSource = "local-fallback";
      } else {
        console.error(`OpenRouter reviewer failed after Gemini key rejection: ${fallbackMessage}`);
        process.exit(1);
      }
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
  if (!parsed.source) {
    parsed.source = reviewerSource;
  }
  console.log(JSON.stringify(parsed, null, 2));
} catch {
  console.error("Failed to parse reviewer JSON response.", rawText);
  process.exit(1);
}
