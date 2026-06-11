/**
 * Shared helpers for async diskwise.suherman.net website deploy workers.
 */
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const { loadDotenv } = require("./load-dotenv.cjs");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const { getProjectAdcPath } = require("./gcp-lib-adc.cjs");

const root = path.join(__dirname, "..");
const websitePrefix = "website/";
const DEPLOY_TARGET = "diskwise-website";

function runGit(args) {
  const r = spawnSync("git", args, { cwd: root, encoding: "utf8", shell: process.platform === "win32" });
  if (r.status !== 0) return "";
  return (r.stdout || "").trim();
}

function getCommitFiles(commit) {
  const output = runGit(["diff-tree", "--no-commit-id", "--name-only", "-r", commit]);
  if (!output) return [];
  return output.split("\n").filter(Boolean);
}

function getCommitFilesInRange(range) {
  const commits = runGit(["rev-list", range]);
  if (!commits) return [];
  const files = new Set();
  for (const commit of commits.split("\n").filter(Boolean)) {
    for (const file of getCommitFiles(commit)) {
      files.add(file);
    }
  }
  return [...files];
}

function commitTouchesWebsite(files) {
  return files.some((file) => file === "website" || file.startsWith(websitePrefix));
}

function isDeployConfigured() {
  loadDotenv(root);
  const projectId = resolveGcpProjectId(root);
  if (!projectId) return false;
  return fs.existsSync(getProjectAdcPath(root));
}

function scheduleWebsiteDeploy() {
  const trigger = path.join(__dirname, "deploy-trigger.cjs");
  spawnSync(process.execPath, [trigger, "--repo", DEPLOY_TARGET], {
    cwd: root,
    stdio: "inherit",
    env: process.env,
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForPushTarget(targetSha, remoteRef, maxWaitMs = 120_000) {
  const started = Date.now();
  while (Date.now() - started < maxWaitMs) {
    const remoteSha = runGit(["rev-parse", remoteRef]);
    if (remoteSha === targetSha) {
      return true;
    }
    if (remoteSha && targetSha) {
      const contained = spawnSync(
        "git",
        ["merge-base", "--is-ancestor", targetSha, remoteRef],
        { cwd: root, shell: process.platform === "win32" },
      );
      if (contained.status === 0) {
        return true;
      }
    }
    await sleep(1000);
  }
  return false;
}

module.exports = {
  root,
  websitePrefix,
  DEPLOY_TARGET,
  runGit,
  getCommitFiles,
  getCommitFilesInRange,
  commitTouchesWebsite,
  isDeployConfigured,
  scheduleWebsiteDeploy,
  waitForPushTarget,
};
