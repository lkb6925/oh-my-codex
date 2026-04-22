import { chmod, cp, mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "./lib/cli-utils.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const packRoot = resolve(__dirname, "..");

const args = parseArgs(process.argv.slice(2));
const target = resolve(args.target || process.cwd());
const skillsRoot = args["skills-root"] || ".agents";
const withConfig = Boolean(args["with-config"]);
const coreOnly = Boolean(args["core-only"]);

await ensureDir(target);
await copyInto(join(packRoot, "AGENTS.md"), join(target, "AGENTS.md"));
await copyTree(join(packRoot, ".codex", "agents"), join(target, ".codex", "agents"));
await copyTree(join(packRoot, ".omx"), join(target, ".omx"));
await copyInto(join(packRoot, "README.md"), join(target, ".codex", "starter-docs", "README.md"));
await copyTree(join(packRoot, "docs"), join(target, ".codex", "starter-docs", "docs"));
await mergeGitignore(join(packRoot, ".gitignore"), join(target, ".gitignore"));
await copyInto(join(packRoot, "scripts", "doctor.mjs"), join(target, "scripts", "doctor.mjs"));
await copyInto(join(packRoot, "scripts", "install.mjs"), join(target, "scripts", "install.mjs"));
await copyInto(join(packRoot, "scripts", "gemini-reviewer.mjs"), join(target, "scripts", "gemini-reviewer.mjs"));
await copyInto(join(packRoot, "scripts", "get-senior-review.sh"), join(target, "scripts", "get-senior-review.sh"));
await copyInto(join(packRoot, "scripts", "run-local-checks.sh"), join(target, "scripts", "run-local-checks.sh"));
await copyInto(join(packRoot, "scripts", "review-gate.mjs"), join(target, "scripts", "review-gate.mjs"));
await copyInto(join(packRoot, "scripts", "vm-ready-check.sh"), join(target, "scripts", "vm-ready-check.sh"));
await copyInto(join(packRoot, "scripts", "postgres-mcp.sh"), join(target, "scripts", "postgres-mcp.sh"));
await copyInto(join(packRoot, "scripts", "factory-night.sh"), join(target, "scripts", "factory-night.sh"));
await copyInto(join(packRoot, "scripts", "factory-status.sh"), join(target, "scripts", "factory-status.sh"));
await copyInto(join(packRoot, "scripts", "factory-watch.sh"), join(target, "scripts", "factory-watch.sh"));
await copyInto(join(packRoot, "scripts", "factory-summary.sh"), join(target, "scripts", "factory-summary.sh"));
await copyInto(join(packRoot, "scripts", "factory-finish.sh"), join(target, "scripts", "factory-finish.sh"));
await copyInto(join(packRoot, "scripts", "factory-self-check.sh"), join(target, "scripts", "factory-self-check.sh"));
await copyInto(join(packRoot, "scripts", "lib", "load-env.sh"), join(target, "scripts", "lib", "load-env.sh"));
await copyInto(join(packRoot, "scripts", "lib", "cli-utils.mjs"), join(target, "scripts", "lib", "cli-utils.mjs"));

if (skillsRoot === ".agents" || skillsRoot === "both") {
  await copyTree(join(packRoot, ".agents", "skills"), join(target, ".agents", "skills"));
}

if (skillsRoot === ".codex" || skillsRoot === "both") {
  await copyTree(join(packRoot, ".agents", "skills"), join(target, ".codex", "skills"));
}

if (withConfig) {
  await copyInto(
    join(packRoot, ".codex", "config.toml.example"),
    join(target, ".codex", "config.toml.example"),
  );
  await copyInto(
    join(packRoot, ".codex", "mcp-servers.example.toml"),
    join(target, ".codex", "mcp-servers.example.toml"),
  );
  try {
    await stat(join(target, ".codex", "config.toml"));
  } catch {
    await copyInto(
      join(packRoot, ".codex", "config.toml"),
      join(target, ".codex", "config.toml"),
    );
  }
}

if (!coreOnly) {
  await copyTree(join(packRoot, ".devcontainer"), join(target, ".devcontainer"));
}

const modeLabel = coreOnly ? "core-only portable starter2" : "full portable starter2";
console.log(`Installed ${modeLabel} into ${target}`);

async function ensureDir(path) {
  await mkdir(path, { recursive: true });
}

async function copyInto(source, destination) {
  await mkdir(dirname(destination), { recursive: true });
  await cp(source, destination, { force: true });
  await preserveExecutableBit(source, destination);
}

async function copyTree(source, destination) {
  try {
    const info = await stat(source);
    if (!info.isDirectory()) {
      await copyInto(source, destination);
      return;
    }
  } catch {
    return;
  }
  await mkdir(dirname(destination), { recursive: true });
  await cp(source, destination, { recursive: true, force: true });
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
  await mkdir(dirname(destination), { recursive: true });
  await writeFile(destination, merged, "utf8");
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
