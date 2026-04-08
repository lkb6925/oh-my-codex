import { mkdir, readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(process.cwd());
const aiDir = join(root, ".ai");
const diffPath = join(aiDir, "diff.txt");
const rawResultPath = join(aiDir, "result.txt");
const reportPath = join(aiDir, "gemini-report.json");

if (!process.env.GEMINI_API_KEY) {
  console.error("GEMINI_API_KEY is missing.");
  process.exit(2);
}

await mkdir(aiDir, { recursive: true });

if (!existsSync(diffPath)) {
  console.error(`Diff file not found: ${diffPath}`);
  process.exit(1);
}

const diff = await readFile(diffPath, "utf8");

if (!diff.trim()) {
  const emptyReport = {
    severity: "PASS",
    issues: [],
  };
  await persistResult(emptyReport);
  console.log("No diff content. Gemini check treated as PASS.");
  process.exit(0);
}

const prompt = `
너는 실리콘밸리의 매우 엄격한 시니어 보안/아키텍처 엔지니어다.

다음 코드 변경(diff)을 분석해서 아래 조건만 판단해라:

[분석 대상]
- 보안 취약점
- 메모리 누수
- 심각한 아키텍처 결함

[규칙]
- 사소한 건 전부 무시
- 문제 없으면 severity = "PASS"
- 치명적이면 반드시 severity = "CRITICAL_HIGH"

[출력 형식 - 반드시 JSON ONLY]
{
  "severity": "PASS | CRITICAL_HIGH",
  "issues": [
    {
      "type": "security | memory | architecture",
      "description": "...",
      "risk": "...",
      "fix": "..."
    }
  ]
}

[분석할 코드]
${diff}
`.trim();

const response = await fetch(
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent",
  {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": process.env.GEMINI_API_KEY,
    },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.1,
        responseMimeType: "application/json",
      },
    }),
  },
);

if (!response.ok) {
  const text = await response.text();
  console.error(`Gemini request failed: ${response.status}`);
  console.error(text);
  process.exit(1);
}

const payload = await response.json();
const text = extractText(payload);
const parsed = parseJsonOnly(text);

await writeFile(rawResultPath, text, "utf8");
await persistResult(parsed);

console.log("=== Gemini 분석 결과 ===");
console.log(JSON.stringify(parsed, null, 2));

if (parsed.severity === "CRITICAL_HIGH") {
  console.error("CRITICAL_HIGH detected.");
  process.exit(1);
}

function extractText(payload) {
  return (
    payload?.candidates?.[0]?.content?.parts
      ?.map((part) => part?.text || "")
      .join("")
      .trim() || ""
  );
}

function parseJsonOnly(text) {
  const normalized = text
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  try {
    return validateResult(JSON.parse(normalized));
  } catch {
    const objectMatch = normalized.match(/\{[\s\S]*\}/);
    if (!objectMatch) {
      console.error("Gemini returned non-JSON output.");
      console.error(normalized);
      process.exit(1);
    }
    try {
      return validateResult(JSON.parse(objectMatch[0]));
    } catch {
      console.error("Gemini JSON parse failed.");
      console.error(normalized);
      process.exit(1);
    }
  }
}

function validateResult(value) {
  const severity = value?.severity === "CRITICAL_HIGH" ? "CRITICAL_HIGH" : "PASS";
  const issues = Array.isArray(value?.issues)
    ? value.issues.map((issue) => ({
        type: issue?.type || "architecture",
        description: issue?.description || "",
        risk: issue?.risk || "",
        fix: issue?.fix || "",
      }))
    : [];

  return { severity, issues };
}

async function persistResult(result) {
  await writeFile(reportPath, `${JSON.stringify(result, null, 2)}\n`, "utf8");
}
