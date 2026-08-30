#!/usr/bin/env node
/**
 * After git push: advance deploy checkpoints when HEAD has no deploy-required
 * changes for a target; otherwise trigger a real deploy (same as deploy:retry).
 *
 * Manual infra target (diskwise-download) is never auto-synced.
 */
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { DEPLOY_TARGETS, deployableTargets, REPO_ROOT } = require("./deploy-config.cjs");
const { readState, findDeployment } = require("./deploy-store.cjs");
const { recordDirectDeployOutcome } = require("./deploy-record-direct.cjs");
const {
  requiresDeployForRepo,
  changedFilesSince,
} = require("./deploy-change-filter.cjs");

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
      console.log(
        "Usage: npm run deploy:sync [-- --repo diskwise-website|diskwise-registry|diskwise-app]",
      );
      process.exit(0);
    }
  }
  return { repo };
}

function lastOutcome(rs, state) {
  if (!rs.lastDeploymentId) return null;
  return findDeployment(state, rs.lastDeploymentId);
}

function planAction(repo, rs, state, head) {
  if (rs.status === "in_progress") return { action: "skip", reason: "in progress" };
  if (rs.status === "queued" && (rs.pid || rs.currentDeploymentId)) {
    return { action: "skip", reason: "queued" };
  }

  const last = lastOutcome(rs, state);
  const outcome = last?.status;
  if (outcome === "failure" || outcome === "cancelled") {
    return { action: "deploy", reason: `last deploy ${outcome}` };
  }

  if (!head || head === rs.lastDeployedSha) {
    return { action: "skip", reason: "up to date" };
  }

  const files = changedFilesSince(rs.lastDeployedSha, head);
  if (requiresDeployForRepo(repo, files)) {
    return { action: "deploy", reason: "deploy-required changes since last deploy" };
  }

  return {
    action: "sync",
    reason: `no ${repo} deploy-required changes since ${(rs.lastDeployedSha || "").slice(0, 7) || "?"} → ${head.slice(0, 7)}`,
  };
}

function syncCheckpoint(target, message) {
  recordDirectDeployOutcome({
    repo: target.repo,
    label: target.label,
    npmScript: target.npmScript,
    status: "success",
    startedAt: new Date().toISOString(),
    exitCode: 0,
    activityMessage: `deploy synced at HEAD — ${message}`,
  });
  console.log(`deploy:sync: ${target.repo} — synced (${message})`);
}

function triggerDeploy(repo) {
  console.log(`deploy:sync: ${repo} — triggering deploy…`);
  spawnSync(process.execPath, [TRIGGER, "--repo", repo], {
    cwd: REPO_ROOT,
    stdio: "inherit",
    env: process.env,
  });
}

function main() {
  const { repo } = parseArgs(process.argv.slice(2));
  const state = readState();
  const head = gitHead();
  if (!head) {
    console.error("deploy:sync: could not read HEAD");
    process.exit(1);
  }

  if (repo && !DEPLOY_TARGETS.find((t) => t.repo === repo && t.npmScript)) {
    console.error(`error: unknown or non-deployable target: ${repo}`);
    process.exit(1);
  }

  const targets = repo
    ? deployableTargets().filter((t) => t.repo === repo)
    : deployableTargets();

  let synced = 0;
  let deployed = 0;
  let skipped = 0;

  for (const target of targets) {
    const rs = state.repos[target.repo] || {};
    const plan = planAction(target.repo, rs, state, head);
    if (plan.action === "skip") {
      console.log(`deploy:sync: ${target.repo} — skip (${plan.reason})`);
      skipped += 1;
      continue;
    }
    if (plan.action === "sync") {
      syncCheckpoint(target, plan.reason);
      synced += 1;
      continue;
    }
    triggerDeploy(target.repo);
    deployed += 1;
  }

  console.log(
    `\ndeploy:sync: done — synced ${synced}, triggered ${deployed}, skipped ${skipped}`,
  );
  if (deployed > 0) console.log("Track progress: npm run ci");
}

main();
