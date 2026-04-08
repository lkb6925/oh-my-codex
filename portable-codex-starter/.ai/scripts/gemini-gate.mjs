import { existsSync, readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join, resolve } from "node:path";

const root = resolve(process.cwd());
const diffScript = join(root, ".ai", "scripts", "write-diff.mjs");
const checkScript = join(root, ".ai", "scripts", "gemini-check.mjs");
const reportPath = join(root, ".ai", "gemini-report.json");
const rawResultPath = join(root, ".ai", "result.txt");

if (!process.env.GEMINI_API_KEY) {
  console.error("GEMINI_API_KEY is required for the Gemini checker gate.");
  process.exit(2);
}

execNode(diffScript);
execNode(checkScript);

if (!existsSync(reportPath)) {
  console.error("Gemini report was not generated.");
  process.exit(1);
}

const report = JSON.parse(readFileSync(reportPath, "utf8"));
const severity = report?.severity || "PASS";

console.log(`Gemini gate severity: ${severity}`);

if (severity === "CRITICAL_HIGH") {
  console.error("Push blocked by Gemini checker. See .ai/gemini-report.json");
  if (existsSync(rawResultPath)) {
    console.error("Raw Gemini output saved to .ai/result.txt");
  }
  process.exit(1);
}

function execNode(scriptPath) {
  execFileSync("node", [scriptPath], {
    cwd: root,
    stdio: "inherit",
  });
}
