import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, basename } from "node:path";

const ROOT = process.cwd();
const PROMPTS_DIR = join(ROOT, "prompts");
const AGENTS_DIR = join(ROOT, ".codex", "agents");

const LOW_ROLES = new Set([
  "explore",
  "explore-harness",
  "style-reviewer",
  "writer",
  "deepsearch",
]);

const HIGH_ROLES = new Set([
  "architect",
  "executor",
  "debugger",
  "planner",
  "analyst",
  "critic",
  "code-reviewer",
  "security-reviewer",
  "designer",
  "git-master",
  "performance-reviewer",
  "quality-reviewer",
  "build-fixer",
  "team-orchestrator",
  "vision",
]);

const ROLE_OVERRIDES = new Map([
  ["explore-harness", { sandbox_mode: "read-only" }],
]);

const BLOCKED_LINE_PATTERNS = [
  /USE_OMX_EXPLORE_CMD/i,
  /\.omx\b/i,
  /\btmux\b/i,
  /OMX_/i,
  /AskUserQuestion/,
  /request_user_input/,
  /state_write/,
  /state_read/,
  /ToolSearch/,
  /mcp__x__ask_codex/,
  /\bralph\b/i,
  /\bultrawork\b/i,
  /\bautopilot\b/i,
  /team verification path/i,
  /launch hints/i,
  /available-agent-types roster/i,
  /staffing \/ role-allocation guidance/i,
];

function stripFrontmatter(content) {
  const match = content.match(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/);
  return match ? content.slice(match[0].length).trim() : content.trim();
}

function parseDescription(content, fallback) {
  const match = content.match(/^---\r?\n[\s\S]*?description:\s*"([^"]+)"[\s\S]*?\r?\n---/m);
  const raw = match?.[1]?.trim() || fallback;
  return raw
    .replace(/\bomx\b/gi, "portable")
    .replace(/\btmux\b/gi, "interactive")
    .replace(/\s+/g, " ")
    .trim();
}

function inferReasoning(role) {
  if (LOW_ROLES.has(role)) return "low";
  if (HIGH_ROLES.has(role)) return "high";
  return "medium";
}

function sanitizeInstructions(content) {
  const lines = stripFrontmatter(content).split(/\r?\n/);
  const filtered = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (/\bomx\b/i.test(line) || BLOCKED_LINE_PATTERNS.some((pattern) => pattern.test(line))) {
      continue;
    }
    if (trimmed.startsWith("<!-- OMX:")) {
      continue;
    }
    filtered.push(line);
  }

  return filtered
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function escapeToml(text) {
  return text.replace(/"{3,}/g, (match) => match.split("").join("\\"));
}

function toToml({ name, description, reasoningEffort, developerInstructions, overrides = {} }) {
  const lines = [
    `# portable-codex-starter agent: ${name}`,
    `name = "${name.replaceAll('"', '\\"')}"`,
    `description = "${description.replaceAll('"', '\\"')}"`,
    `model_reasoning_effort = "${reasoningEffort}"`,
  ];

  for (const [key, value] of Object.entries(overrides)) {
    if (typeof value === "string") {
      lines.push(`${key} = "${value.replaceAll('"', '\\"')}"`);
    }
  }

  lines.push(
    'developer_instructions = """',
    escapeToml(developerInstructions),
    '"""',
    "",
  );

  return lines.join("\n");
}

async function main() {
  if (!existsSync(PROMPTS_DIR)) {
    throw new Error(`prompts directory not found: ${PROMPTS_DIR}`);
  }

  await mkdir(AGENTS_DIR, { recursive: true });

  const files = (await readdir(PROMPTS_DIR))
    .filter((file) => file.endsWith(".md"))
    .sort();

  await Promise.all(
    files.map(async (file) => {
      const role = basename(file, ".md");
      const source = await readFile(join(PROMPTS_DIR, file), "utf8");
      const description = parseDescription(source, `${role} custom agent`);
      const developerInstructions = sanitizeInstructions(source);
      const reasoningEffort = inferReasoning(role);
      const overrides = ROLE_OVERRIDES.get(role) || {};
      const toml = toToml({
        name: role,
        description,
        reasoningEffort,
        developerInstructions,
        overrides,
      });
      await writeFile(join(AGENTS_DIR, `${role}.toml`), toml, "utf8");
    }),
  );

  console.log(`Generated ${files.length} agent files in ${AGENTS_DIR}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
