import { readFile, readdir, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "./lib/cli-utils.mjs";

const args = parseArgs(process.argv.slice(2));
const target = resolve(args.target || process.cwd());
const coreOnly = Boolean(args["core-only"]);
const skillsRoot = args["skills-root"] || ".agents";

const expected = {
  agents: 33,
  skills: 15,
  githubAgents: 5,
  githubInstructions: 6,
  githubSkills: 4,
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
const aiScriptsPath = join(target, ".ai", "scripts");
const gitHooksPath = join(target, ".githooks");
const prePushHookPath = join(gitHooksPath, "pre-push");
const githubAgentsPath = join(target, ".github", "agents");
const githubInstructionsPath = join(target, ".github", "instructions");
const githubSkillsPath = join(target, ".github", "skills");

const agentCount = await countAgentFiles(agentsPath);
const agentsSkillScan = await inspectSkillDirectories(agentsSkillsPath);
const codexSkillScan = await inspectSkillDirectories(codexSkillsPath);

if (skillsRoot === ".agents") {
  checks.push(checkExists(".agents/skills", agentsSkillsPath));
  checks.push({
    name: "skill count",
    ok: agentsSkillScan.count === expected.skills,
    detail: `${agentsSkillScan.count}/${expected.skills} in .agents/skills`,
  });
  checks.push(checkOptionalIssues(".agents/skills structure", agentsSkillScan.issues));
} else if (skillsRoot === ".codex") {
  checks.push(checkExists(".codex/skills", codexSkillsPath));
  checks.push({
    name: "skill count",
    ok: codexSkillScan.count === expected.skills,
    detail: `${codexSkillScan.count}/${expected.skills} in .codex/skills`,
  });
  checks.push(checkOptionalIssues(".codex/skills structure", codexSkillScan.issues));
} else if (skillsRoot === "both") {
  checks.push(checkExists(".agents/skills", agentsSkillsPath));
  checks.push(checkExists(".codex/skills", codexSkillsPath));
  checks.push({
    name: "skill count (.agents)",
    ok: agentsSkillScan.count === expected.skills,
    detail: `${agentsSkillScan.count}/${expected.skills}`,
  });
  checks.push({
    name: "skill count (.codex)",
    ok: codexSkillScan.count === expected.skills,
    detail: `${codexSkillScan.count}/${expected.skills}`,
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
checks.push(checkOptional("starter-docs/README.md", starterDocsReadmePath));
checks.push(checkOptional("starter-docs/docs/automation-playbook.md", starterDocsAutomationPath));
checks.push(checkExists(".ai/scripts", aiScriptsPath));
checks.push(checkExists(".githooks", gitHooksPath));
checks.push(checkExists(".ai/scripts/write-diff.mjs", join(aiScriptsPath, "write-diff.mjs")));
checks.push(checkExists(".ai/scripts/gemini-check.mjs", join(aiScriptsPath, "gemini-check.mjs")));
checks.push(checkExists(".ai/scripts/gemini-gate.mjs", join(aiScriptsPath, "gemini-gate.mjs")));
checks.push(checkExists(".githooks/pre-push", prePushHookPath));
checks.push(await checkExecutable(".githooks/pre-push executable", prePushHookPath));

const configUsesContext7 = existsSync(configPath)
  ? (await readTextIfExists(configPath)).includes("[mcp_servers.context7]")
  : false;
const geminiGateExists = existsSync(join(target, ".ai", "scripts", "gemini-gate.mjs"));

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

if (geminiGateExists) {
  checks.push({
    name: "GEMINI_API_KEY",
    ok: Boolean(process.env.GEMINI_API_KEY),
    optional: true,
    detail: process.env.GEMINI_API_KEY
      ? "set"
      : "missing; Gemini checker gate and pre-push hook will fail",
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
  checks.push(
    checkExists(".github/copilot-instructions.md", join(target, ".github", "copilot-instructions.md")),
  );
  checks.push(checkExists(".github/agents", githubAgentsPath));
  checks.push(checkExists(".github/instructions", githubInstructionsPath));
  checks.push(checkExists(".github/skills", githubSkillsPath));
  checks.push(checkExists(".github/hooks", join(target, ".github", "hooks")));
  checks.push(
    checkExists(
      ".github/workflows/copilot-setup-steps.yml",
      join(target, ".github", "workflows", "copilot-setup-steps.yml"),
    ),
  );
  checks.push(
    checkExists(
      ".github/workflows/portable-quality-gate.yml",
      join(target, ".github", "workflows", "portable-quality-gate.yml"),
    ),
  );

  const githubAgentCount = await countMarkdownFiles(githubAgentsPath, ".agent.md");
  const githubInstructionCount = await countMarkdownFiles(githubInstructionsPath, ".instructions.md");
  const githubSkillScan = await inspectSkillDirectories(githubSkillsPath);

  checks.push({
    name: "GitHub agent count",
    ok: githubAgentCount === expected.githubAgents,
    detail: `${githubAgentCount}/${expected.githubAgents}`,
  });
  checks.push({
    name: "GitHub instruction count",
    ok: githubInstructionCount === expected.githubInstructions,
    detail: `${githubInstructionCount}/${expected.githubInstructions}`,
  });
  checks.push({
    name: "GitHub skill count",
    ok: githubSkillScan.count === expected.githubSkills,
    detail: `${githubSkillScan.count}/${expected.githubSkills}`,
  });
  checks.push(checkOptionalIssues("GitHub skills structure", githubSkillScan.issues));
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

async function countMarkdownFiles(path, suffix) {
  if (!existsSync(path)) return 0;
  const entries = await readdir(path, { withFileTypes: true });
  return entries.filter((entry) => entry.isFile() && entry.name.endsWith(suffix)).length;
}

async function checkExecutable(name, path) {
  if (!existsSync(path)) {
    return {
      name,
      ok: false,
      optional: false,
      detail: "missing",
    };
  }

  try {
    const info = await stat(path);
    return {
      name,
      ok: Boolean(info.mode & 0o111),
      optional: false,
      detail: Boolean(info.mode & 0o111) ? "" : "not executable",
    };
  } catch (error) {
    return {
      name,
      ok: false,
      optional: false,
      detail: error?.code || "stat failed",
    };
  }
}

async function readTextIfExists(path) {
  try {
    return await readFile(path, "utf8");
  } catch {
    return "";
  }
}
