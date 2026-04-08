import { mkdir, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join, resolve } from "node:path";

const root = resolve(process.cwd());
const aiDir = join(root, ".ai");
const diffPath = join(aiDir, "diff.txt");

await mkdir(aiDir, { recursive: true });

const diff = generateDiff();
await writeFile(diffPath, diff, "utf8");

console.log(`Wrote diff to ${diffPath}`);
console.log(diff.trim() ? "Diff contains changes." : "No diff content.");

function generateDiff() {
  const stagedDiff = runGitDiff(["diff", "--cached", "--binary", "--no-color"]);
  if (stagedDiff.trim()) {
    return stagedDiff;
  }

  const workingTreeDiff = runGitDiff(["diff", "--binary", "--no-color"]);
  if (workingTreeDiff.trim()) {
    return workingTreeDiff;
  }

  const upstreamRef = getUpstreamRef();
  if (upstreamRef) {
    const upstreamDiff = runGitDiff(["diff", "--binary", "--no-color", `${upstreamRef}...HEAD`]);
    if (upstreamDiff.trim()) {
      return upstreamDiff;
    }
  }

  const baseRef = process.env.GITHUB_BASE_REF;
  if (baseRef) {
    const remoteRef = `origin/${baseRef}`;
    if (hasGitRef(remoteRef)) {
      const prDiff = runGitDiff(["diff", "--binary", "--no-color", `${remoteRef}...HEAD`]);
      if (prDiff.trim()) return prDiff;
    }
  }

  if (hasGitRef("HEAD^")) {
    const headDiff = runGitDiff(["diff", "--binary", "--no-color", "HEAD^", "HEAD"]);
    if (headDiff.trim()) return headDiff;
  }

  if (hasGitRef("HEAD")) {
    return runGitDiff(["diff", "--binary", "--no-color", "HEAD"]);
  }

  return "";
}

function runGitDiff(args) {
  try {
    return execFileSync("git", args, { cwd: root, encoding: "utf8" });
  } catch {
    return "";
  }
}

function hasGitRef(ref) {
  if (!existsSync(join(root, ".git")) && !existsSync(join(root, ".git", "HEAD"))) {
    return false;
  }

  try {
    execFileSync("git", ["rev-parse", "--verify", ref], {
      cwd: root,
      stdio: "ignore",
    });
    return true;
  } catch {
    return false;
  }
}

function getUpstreamRef() {
  try {
    return execFileSync("git", ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], {
      cwd: root,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}
