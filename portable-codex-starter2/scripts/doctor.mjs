import { readFile, readdir, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "./lib/cli-utils.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const packRoot = resolve(__dirname, "..");

const args = parseArgs(process.argv.slice(2));
const target = resolve(args.target || process.cwd());
const coreOnly = Boolean(args["core-only"]);
const skillsRoot = args["skills-root"] || ".agents";
const checkingPackRoot = target === packRoot;

const expected = {
  agents: 4,
  skills: 15,
};

const checks = [];

checks.push(checkExists("AGENTS.md", join(target, "AGENTS.md")));
checks.push(checkExists(".codex/agents", join(target, ".codex", "agents")));

const agentsPath = join(target, ".codex", "agents");
const agentsSkillsPath = join(target, ".agents", "skills");
const codexSkillsPath = join(target, ".codex", "skills");
const configPath = join(target, ".codex", "config.toml");
const configExamplePath = join(target, ".codex", "config.toml.example");
const mcpExamplePath = join(target, ".codex", "mcp-servers.example.toml");
const starterDocsReadmePath = join(target, ".codex", "starter-docs", "README.md");
const starterDocsAutomationPath = join(target, ".codex", "starter-docs", "docs", "automation-playbook.md");
const checkpointsPath = join(target, ".omx", "checkpoints");
const checkpointsGitkeepPath = join(checkpointsPath, ".gitkeep");

const agentCount = await countAgentFiles(agentsPath);
const agentsSkillScan = await inspectSkillDirectories(agentsSkillsPath);
const codexSkillScan = await inspectSkillDirectories(codexSkillsPath);

if (skillsRoot === ".agents") {
  checks.push(checkExists(".agents/skills", agentsSkillsPath));
  checks.push({
    name: "skill count",
    ok: agentsSkillScan.count >= expected.skills,
    detail: `${agentsSkillScan.count} (minimum ${expected.skills}) in .agents/skills`,
  });
  checks.push(checkOptionalIssues(".agents/skills structure", agentsSkillScan.issues));
} else if (skillsRoot === ".codex") {
  checks.push(checkExists(".codex/skills", codexSkillsPath));
  checks.push({
    name: "skill count",
    ok: codexSkillScan.count >= expected.skills,
    detail: `${codexSkillScan.count} (minimum ${expected.skills}) in .codex/skills`,
  });
  checks.push(checkOptionalIssues(".codex/skills structure", codexSkillScan.issues));
} else if (skillsRoot === "both") {
  checks.push(checkExists(".agents/skills", agentsSkillsPath));
  checks.push(checkExists(".codex/skills", codexSkillsPath));
  checks.push({
    name: "skill count (.agents)",
    ok: agentsSkillScan.count >= expected.skills,
    detail: `${agentsSkillScan.count} (minimum ${expected.skills})`,
  });
  checks.push({
    name: "skill count (.codex)",
    ok: codexSkillScan.count >= expected.skills,
    detail: `${codexSkillScan.count} (minimum ${expected.skills})`,
  });
  checks.push(checkOptionalIssues(".agents/skills structure", agentsSkillScan.issues));
  checks.push(checkOptionalIssues(".codex/skills structure", codexSkillScan.issues));
} else {
  checks.push({
    name: "skills-root",
    ok: false,
    optional: false,
    detail: `unsupported value: ${skillsRoot}`,
  });
}

checks.push({
  name: "agent count",
  ok: agentCount === expected.agents,
  detail: `${agentCount}/${expected.agents}`,
});
checks.push(checkOptional("config.toml", configPath));
checks.push(checkOptional("config.toml.example", configExamplePath));
checks.push(checkOptional("mcp-servers.example.toml", mcpExamplePath));
if (!checkingPackRoot) {
  checks.push(checkOptional("starter-docs/README.md", starterDocsReadmePath));
  checks.push(checkOptional("starter-docs/docs/automation-playbook.md", starterDocsAutomationPath));
}

const configUsesContext7 = existsSync(configPath)
  ? (await readTextIfExists(configPath)).includes("[mcp_servers.context7]")
  : false;
const configText = existsSync(configPath) ? await readTextIfExists(configPath) : "";
const configUsesPostgres = configText.includes("[mcp_servers.postgres]");
const postgresHasHardcodedUrl = /postgres(ql)?:\/\//.test(configText);
const postgresUsesEnvLauncher =
  configText.includes('command = "bash"') &&
  configText.includes('args = ["scripts/postgres-mcp.sh"]');

if (configUsesContext7) {
  checks.push({
    name: "CONTEXT7_API_KEY",
    ok: Boolean(process.env.CONTEXT7_API_KEY),
    optional: true,
    detail: process.env.CONTEXT7_API_KEY
      ? "set"
      : "missing; Context7 may hit anonymous rate limits",
  });
}

checks.push({
  name: "postgres MCP configured",
  ok: configUsesPostgres,
  optional: true,
  detail: configUsesPostgres ? "present" : "missing; DB-backed apps may drift from the real schema",
});
checks.push(checkOptional(".omx/checkpoints", checkpointsPath));
checks.push(checkOptional(".omx/checkpoints/.gitkeep", checkpointsGitkeepPath));
if (configUsesPostgres) {
  checks.push({
    name: "postgres MCP uses env launcher",
    ok: postgresUsesEnvLauncher,
    optional: true,
    detail: postgresUsesEnvLauncher
      ? "scripts/postgres-mcp.sh"
      : "prefer bash launcher + POSTGRES_MCP_DSN to avoid committed credentials",
  });
  checks.push({
    name: "postgres DSN not hardcoded in config",
    ok: !postgresHasHardcodedUrl,
    optional: true,
    detail: postgresHasHardcodedUrl
      ? "remove plaintext DSN and inject POSTGRES_MCP_DSN via environment"
      : "no DSN literal found",
  });
}

if (!coreOnly) {
  checks.push(checkExists(".devcontainer/devcontainer.json", join(target, ".devcontainer", "devcontainer.json")));
  checks.push(
    checkExists(
      ".devcontainer/scripts/post-create.sh",
      join(target, ".devcontainer", "scripts", "post-create.sh"),
    ),
  );
  checks.push(
    checkExists(
      ".devcontainer/scripts/update-content.sh",
      join(target, ".devcontainer", "scripts", "update-content.sh"),
    ),
  );
}

const hasFailures = checks.some((check) => !check.ok && !check.optional);
const hasWarnings = checks.some((check) => !check.ok && check.optional);

console.log(`Portable Codex Starter doctor: ${target}`);
for (const check of checks) {
  const icon = check.ok ? "[OK]" : check.optional ? "[!!]" : "[XX]";
  const suffix = check.detail ? ` (${check.detail})` : "";
  console.log(`${icon} ${check.name}${suffix}`);
}

if (hasFailures) {
  console.error("\nDoctor found blocking issues.");
  process.exitCode = 1;
} else if (hasWarnings) {
  console.log("\nDoctor found no blocking issues, but some optional checks are unmet.");
} else {
  console.log("\nDoctor passed.");
}

function checkExists(name, path) {
  return {
    name,
    ok: existsSync(path),
    optional: false,
  };
}

function checkOptional(name, path) {
  return {
    name,
    ok: existsSync(path),
    optional: true,
  };
}

function checkOptionalIssues(name, issues) {
  return {
    name,
    ok: issues.length === 0,
    optional: true,
    detail: issues.length === 0 ? "" : issues.join("; "),
  };
}

async function countAgentFiles(path) {
  if (!existsSync(path)) return 0;
  const entries = await readdir(path, { withFileTypes: true });
  return entries.filter((entry) => entry.isFile() && entry.name.endsWith(".toml")).length;
}

async function inspectSkillDirectories(path) {
  if (!existsSync(path)) return { count: 0, issues: [] };
  const entries = await readdir(path, { withFileTypes: true });
  let count = 0;
  const issues = [];
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const skillPath = join(path, entry.name, "SKILL.md");
    try {
      await stat(skillPath);
      count += 1;
    } catch (error) {
      const reason = error?.code === "ENOENT" ? "missing SKILL.md" : error?.code || "stat failed";
      issues.push(`${entry.name}: ${reason}`);
    }
  }
  return { count, issues };
}

async function readTextIfExists(path) {
  try {
    return await readFile(path, "utf8");
  } catch {
    return "";
  }
}
