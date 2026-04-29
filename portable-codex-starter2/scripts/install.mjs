import { chmod, cp, mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "./lib/cli-utils.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const packRoot = resolve(__dirname, "..");
const starterDocsRoot = await resolveStarterDocsRoot();

const args = parseArgs(process.argv.slice(2));
const target = resolve(args.target || process.cwd());
const withConfig = Boolean(args["with-config"]);
const coreOnly = Boolean(args["core-only"]);
const withAgents = Boolean(args["with-agents"]);
const withSkills = Boolean(args["with-skills"] || args["skills-root"]);
const skillsRoot = withSkills ? String(args["skills-root"] || ".agents") : "none";
const warnings = [];

await ensureDir(target);
await copyRequiredInto(join(packRoot, "AGENTS.md"), join(target, "AGENTS.md"));

if (withAgents) {
  await copyOptionalTree(join(packRoot, ".codex", "agents"), join(target, ".codex", "agents"), "optional starter agents");
} else {
  warnings.push("Skipped .codex/agents: overlay mode preserves existing OMX/Codex agents. Use --with-agents to install starter example agents.");
}

// Only copy durable recovery points. Runtime state/logs/runs stay local to the VM.
await copyOptionalTree(join(packRoot, ".omx", "checkpoints"), join(target, ".omx", "checkpoints"), "checkpoints");
await copyOptionalTree(join(packRoot, ".omx", "hooks"), join(target, ".omx", "hooks"), "hooks");
await copyOptionalInto(join(starterDocsRoot, "README.md"), join(target, ".codex", "starter-docs", "README.md"), "starter docs README");
await copyOptionalTree(join(starterDocsRoot, "docs"), join(target, ".codex", "starter-docs", "docs"), "starter docs");
await mergeGitignore(join(packRoot, ".gitignore"), join(target, ".gitignore"));
await copyRequiredInto(join(packRoot, "scripts", "doctor.mjs"), join(target, "scripts", "doctor.mjs"));
await copyRequiredInto(join(packRoot, "scripts", "install.mjs"), join(target, "scripts", "install.mjs"));
await copyRequiredInto(join(packRoot, "scripts", "gemini-reviewer.mjs"), join(target, "scripts", "gemini-reviewer.mjs"));
await copyRequiredInto(join(packRoot, "scripts", "get-senior-review.sh"), join(target, "scripts", "get-senior-review.sh"));
await copyRequiredInto(join(packRoot, "scripts", "run-local-checks.sh"), join(target, "scripts", "run-local-checks.sh"));
await copyRequiredInto(join(packRoot, "scripts", "review-gate.mjs"), join(target, "scripts", "review-gate.mjs"));
await copyRequiredInto(join(packRoot, "scripts", "harness-event.mjs"), join(target, "scripts", "harness-event.mjs"));
await copyRequiredInto(join(packRoot, "scripts", "factory-team.sh"), join(target, "scripts", "factory-team.sh"));
await copyRequiredInto(join(packRoot, "scripts", "factory-team-status.sh"), join(target, "scripts", "factory-team-status.sh"));
await copyRequiredInto(join(packRoot, "scripts", "factory-team-await.sh"), join(target, "scripts", "factory-team-await.sh"));
await copyRequiredInto(join(packRoot, "scripts", "factory-team-summary.sh"), join(target, "scripts", "factory-team-summary.sh"));
await copyRequiredInto(join(packRoot, "scripts", "factory-team-shutdown.sh"), join(target, "scripts", "factory-team-shutdown.sh"));
await copyRequiredInto(join(packRoot, "scripts", "vm-ready-check.sh"), join(target, "scripts", "vm-ready-check.sh"));
await copyRequiredInto(join(packRoot, "scripts", "postgres-mcp.sh"), join(target, "scripts", "postgres-mcp.sh"));
await copyRequiredInto(join(packRoot, "factory"), join(target, "factory"));
await copyRequiredInto(join(packRoot, "factory-night"), join(target, "factory-night"));
await copyRequiredInto(join(packRoot, "factory-team"), join(target, "factory-team"));
await copyRequiredInto(join(packRoot, "scripts", "factory-night.sh"), join(target, "scripts", "factory-night.sh"));
await copyRequiredInto(join(packRoot, "scripts", "factory-day.sh"), join(target, "scripts", "factory-day.sh"));
await copyRequiredInto(join(packRoot, "scripts", "factory-status.sh"), join(target, "scripts", "factory-status.sh"));
await copyRequiredInto(join(packRoot, "scripts", "factory-watch.sh"), join(target, "scripts", "factory-watch.sh"));
await copyRequiredInto(join(packRoot, "scripts", "factory-summary.sh"), join(target, "scripts", "factory-summary.sh"));
await copyRequiredInto(join(packRoot, "scripts", "factory-finish.sh"), join(target, "scripts", "factory-finish.sh"));
await copyRequiredInto(join(packRoot, "scripts", "factory-self-check.sh"), join(target, "scripts", "factory-self-check.sh"));
await copyRequiredInto(join(packRoot, "scripts", "lib", "load-env.sh"), join(target, "scripts", "lib", "load-env.sh"));
await copyRequiredInto(join(packRoot, "scripts", "lib", "cli-utils.mjs"), join(target, "scripts", "lib", "cli-utils.mjs"));

if (skillsRoot === ".agents" || skillsRoot === "both") {
  await copyOptionalTree(join(packRoot, ".agents", "skills"), join(target, ".agents", "skills"), "optional starter skills (.agents)");
}

if (skillsRoot === ".codex" || skillsRoot === "both") {
  await copyOptionalTree(join(packRoot, ".agents", "skills"), join(target, ".codex", "skills"), "optional starter skills (.codex)");
}

if (!["none", ".agents", ".codex", "both"].includes(skillsRoot)) {
  throw new Error(`unsupported --skills-root value: ${skillsRoot}`);
}

if (skillsRoot === "none") {
  warnings.push("Skipped starter skills: overlay mode preserves existing OMX/Codex skills. Use --with-skills or --skills-root=.agents|.codex|both to install them.");
}

if (withConfig) {
  await copyOptionalInto(
    join(packRoot, ".codex", "config.toml.example"),
    join(target, ".codex", "config.toml.example"),
    "config example",
  );
  await copyOptionalInto(
    join(packRoot, ".codex", "mcp-servers.example.toml"),
    join(target, ".codex", "mcp-servers.example.toml"),
    "mcp servers example",
  );
  try {
    await stat(join(target, ".codex", "config.toml"));
  } catch {
    await copyOptionalInto(
      join(packRoot, ".codex", "config.toml"),
      join(target, ".codex", "config.toml"),
      "config.toml",
    );
  }
}

if (!coreOnly) {
  await copyOptionalTree(join(packRoot, ".devcontainer"), join(target, ".devcontainer"), "devcontainer");
}

const modeLabel = coreOnly ? "core-only overlay starter2" : "full overlay starter2";
console.log(`Installed ${modeLabel} into ${target}`);
if (warnings.length > 0) {
  console.log("\nOverlay notes:");
  for (const warning of [...new Set(warnings)]) {
    console.log(`- ${warning}`);
  }
}

async function ensureDir(path) {
  await mkdir(path, { recursive: true });
}

async function copyRequiredInto(source, destination) {
  await mkdir(dirname(destination), { recursive: true });
  await cp(source, destination, { force: true });
  await preserveExecutableBit(source, destination);
}

async function copyOptionalInto(source, destination, label) {
  try {
    await copyRequiredInto(source, destination);
  } catch (error) {
    if (isSkippableOptionalCopyError(error)) {
      warnings.push(`Skipped ${label}: could not copy to ${destination} (${error.code}).`);
      return;
    }
    throw error;
  }
}

async function copyOptionalTree(source, destination, label) {
  try {
    const info = await stat(source);
    if (!info.isDirectory()) {
      await copyOptionalInto(source, destination, label);
      return;
    }
  } catch (error) {
    if (error?.code === "ENOENT") return;
    throw error;
  }

  try {
    await mkdir(dirname(destination), { recursive: true });
    await cp(source, destination, { recursive: true, force: true });
  } catch (error) {
    if (isSkippableOptionalCopyError(error)) {
      warnings.push(`Skipped ${label}: could not copy to ${destination} (${error.code}).`);
      return;
    }
    throw error;
  }
}

async function mergeGitignore(source, destination) {
  let sourceText = "";
  try {
    sourceText = await readFile(source, "utf8");
  } catch {
    return;
  }

  const sourceLines = sourceText
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  let destinationText = "";
  try {
    destinationText = await readFile(destination, "utf8");
  } catch {
    destinationText = "";
  }

  const destinationLines = new Set(
    destinationText
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line.length > 0),
  );

  const missingLines = sourceLines.filter((line) => !destinationLines.has(line));
  if (missingLines.length === 0) {
    return;
  }

  const separator = destinationText.length > 0 && !destinationText.endsWith("\n") ? "\n" : "";
  const prefix = destinationText.length > 0 ? "\n# portable-codex-starter2\n" : "";
  const merged = `${destinationText}${separator}${prefix}${missingLines.join("\n")}\n`;
  try {
    await mkdir(dirname(destination), { recursive: true });
    await writeFile(destination, merged, "utf8");
  } catch (error) {
    if (isSkippableOptionalCopyError(error)) {
      warnings.push(`Skipped .gitignore merge: could not update ${destination} (${error.code}).`);
      return;
    }
    throw error;
  }
}

function isSkippableOptionalCopyError(error) {
  return ["EROFS", "EACCES", "EPERM", "ENOENT"].includes(error?.code);
}

async function resolveStarterDocsRoot() {
  const preferred = join(packRoot, "portable-codex-starter2");
  try {
    const info = await stat(preferred);
    if (info.isDirectory()) {
      return preferred;
    }
  } catch {
    // Fall back to the repository root when the nested docs mirror is absent.
  }
  return packRoot;
}

async function preserveExecutableBit(source, destination) {
  let sourceInfo;
  try {
    sourceInfo = await stat(source);
  } catch {
    return;
  }

  const executableBits = sourceInfo.mode & 0o111;
  if (executableBits === 0) {
    return;
  }

  const targetMode = sourceInfo.mode & 0o777;
  await chmod(destination, targetMode);
}
