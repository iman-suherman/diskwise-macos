#!/usr/bin/env node
/**
 * Retry website deploy for failed, cancelled, or undeployed commits.
 */
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { DEPLOY_TARGETS, deployableTargets, REPO_ROOT } = require("./deploy-config.cjs");
const { readState, findDeployment } = require("./deploy-store.cjs");

const TRIGGER = path.join(REPO_ROOT, "scripts/deploy-trigger.cjs");

function gitHead() {
  const result = spawnSync("git", ["rev-parse", "HEAD"], {
    cwd: REPO_ROOT,
    encoding: "utf8",
  });
  return result.status === 0 ? result.stdout.trim() : null;
}

function parseArgs(argv) {
  let repo = null;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--repo" && argv[i + 1]) repo = argv[++i];
    else if (argv[i] === "-h" || argv[i] === "--help") {
      console.log(`Usage: npm run deploy:retry [-- --repo diskwise-website|diskwise-app]`);
      process.exit(0);
    }
  }
  return { repo };
}

function needsRetry(rs, lastDeploy) {
  if (rs.status === "in_progress") return false;
  if (rs.status === "queued" && !rs.pid && !rs.currentDeploymentId) return true;
  if (rs.status === "queued") return false;
  const outcome = lastDeploy?.status;
  if (outcome === "failure" || outcome === "cancelled") return true;
  const head = gitHead();
  return Boolean(head && head !== rs.lastDeployedSha);
}

function reposNeedingRetry(state) {
  const names = [];
  for (const target of deployableTargets()) {
    const rs = state.repos[target.repo] || {};
    const lastDeploy = rs.lastDeploymentId
      ? findDeployment(state, rs.lastDeploymentId)
      : null;
    if (needsRetry(rs, lastDeploy)) names.push(target.repo);
  }
  return names;
}

function main() {
  const { repo } = parseArgs(process.argv.slice(2));
  const state = readState();
  const targets = repo ? [repo] : reposNeedingRetry(state);

  if (repo && !DEPLOY_TARGETS.find((t) => t.repo === repo && t.npmScript)) {
    console.error(`error: unknown or non-deployable target: ${repo}`);
    process.exit(1);
  }

  if (targets.length === 0) {
    console.log("No targets need retry (all idle and up to date).");
    process.exit(0);
  }

  console.log(`Retrying deploy for: ${targets.join(", ")}`);
  console.log("Track progress: npm run ci\n");

  for (const name of targets) {
    spawnSync(process.execPath, [TRIGGER, "--repo", name], {
      cwd: REPO_ROOT,
      stdio: "inherit",
      env: process.env,
    });
  }
}

main();
