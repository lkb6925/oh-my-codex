import { chmod, cp, mkdir, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
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
await copyInto(join(packRoot, "README.md"), join(target, ".codex", "starter-docs", "README.md"));
await copyTree(join(packRoot, "docs"), join(target, ".codex", "starter-docs", "docs"));
await copyTree(join(packRoot, ".ai"), join(target, ".ai"));
await copyTree(join(packRoot, ".githooks"), join(target, ".githooks"));
await ensureHookExecutable(join(target, ".githooks", "pre-push"));

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
  await copyInto(
    join(packRoot, ".github", "copilot-instructions.md"),
    join(target, ".github", "copilot-instructions.md"),
  );
  await copyTree(join(packRoot, ".github", "instructions"), join(target, ".github", "instructions"));
  await copyTree(join(packRoot, ".github", "agents"), join(target, ".github", "agents"));
  await copyTree(join(packRoot, ".github", "skills"), join(target, ".github", "skills"));
  await copyTree(join(packRoot, ".github", "hooks"), join(target, ".github", "hooks"));
  await copyTree(join(packRoot, ".github", "workflows"), join(target, ".github", "workflows"));
}

const modeLabel = coreOnly ? "core-only portable starter" : "full portable starter";

configureGitHooks(target);
console.log(`Installed ${modeLabel} into ${target}`);

async function ensureDir(path) {
  await mkdir(path, { recursive: true });
}

async function copyInto(source, destination) {
  await mkdir(dirname(destination), { recursive: true });
  await cp(source, destination, { force: true });
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

function configureGitHooks(target) {
  if (!existsSync(join(target, ".git")) || !existsSync(join(target, ".githooks"))) {
    return;
  }

  try {
    execFileSync("git", ["config", "core.hooksPath", ".githooks"], {
      cwd: target,
      stdio: "ignore",
    });
  } catch {
    // Best effort only. Doctor and README explain the expected hook path.
  }
}

async function ensureHookExecutable(path) {
  try {
    await chmod(path, 0o755);
  } catch {
    // Best effort only. Doctor will flag a missing or non-executable hook.
  }
}
