#!/usr/bin/env node
/**
 * Fire-and-forget deploy trigger — returns immediately (safe for git hooks).
 *
 * Usage:
 *   node scripts/deploy-trigger.cjs --repo diskwise-website
 */

const path = require("node:path");
const { spawn, spawnSync } = require("node:child_process");
const { REPO_ROOT, getDeployTarget } = require("./deploy-config.cjs");
const {
  updateState,
  getRepoState,
  readState,
  recordActivity,
  isStuckQueued,
} = require("./deploy-store.cjs");

const RUNNER = path.join(REPO_ROOT, "scripts/deploy-runner.cjs");

function parseArgs(argv) {
  let repo = null;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--repo" && argv[i + 1]) repo = argv[++i];
    else if (argv[i] === "-h" || argv[i] === "--help") {
      console.log("Usage: node scripts/deploy-trigger.cjs --repo <diskwise-website|diskwise-app>");
      process.exit(0);
    }
  }
  if (!repo) {
    console.error("error: --repo is required");
    process.exit(1);
  }
  return { repo };
}

function gitHead() {
  const result = spawnSync("git", ["rev-parse", "HEAD"], {
    cwd: REPO_ROOT,
    encoding: "utf8",
  });
  return result.status === 0 ? result.stdout.trim() : null;
}

function gitBranch() {
  const result = spawnSync("git", ["rev-parse", "--abbrev-ref", "HEAD"], {
    cwd: REPO_ROOT,
    encoding: "utf8",
  });
  return result.status === 0 ? result.stdout.trim() || "main" : "main";
}

const QUEUED_GRACE_MS = Number.parseInt(process.env.DISKWise_QUEUED_GRACE_MS || "15000", 10);

function isRunning(repo) {
  const rs = readState().repos[repo];
  return rs?.status === "in_progress";
}

/** Queued with spawn in flight (runner not yet marked in_progress). */
function isQueuedPending(rs, state) {
  if (rs?.status !== "queued") return false;
  if (rs.pid || rs.currentDeploymentId) return true;
  const updated = state?.updatedAt ? new Date(state.updatedAt).getTime() : 0;
  return Date.now() - updated < QUEUED_GRACE_MS;
}

function spawnBackgroundDeploy(repo, sha) {
  const child = spawn(
    process.execPath,
    [RUNNER, "--repo", repo, "--sha", sha, "--background"],
    {
      cwd: REPO_ROOT,
      detached: true,
      stdio: "ignore",
      env: process.env,
    },
  );
  child.unref();
  return child.pid || null;
}

function main() {
  const { repo } = parseArgs(process.argv.slice(2));
  const target = getDeployTarget(repo);

  if (!target?.npmScript) {
    process.exit(0);
  }

  const sha = gitHead();
  const branch = target.branch || gitBranch();
  if (!sha) {
    process.exit(0);
  }

  if (isRunning(repo)) {
    updateState((state) => {
      const rs = getRepoState(state, repo);
      rs.headSha = sha;
      rs.branch = branch;
      recordActivity(state, {
        type: "trigger_skipped",
        repo,
        sha,
        shortSha: sha.slice(0, 7),
        message: "deploy already in progress",
      });
      return state;
    });
    process.exit(0);
  }

  const prior = readState();
  const priorRs = prior.repos[repo];
  if (isQueuedPending(priorRs, prior)) {
    updateState((state) => {
      const rs = getRepoState(state, repo);
      rs.headSha = sha;
      rs.branch = branch;
      recordActivity(state, {
        type: "trigger_skipped",
        repo,
        sha,
        shortSha: sha.slice(0, 7),
        message: "deploy already queued",
      });
      return state;
    });
    process.exit(0);
  }

  if (isStuckQueued(priorRs)) {
    updateState((state) => {
      recordActivity(state, {
        type: "stale_recovered",
        repo,
        sha,
        shortSha: sha.slice(0, 7),
        message: "cleared stuck queued state",
      });
      return state;
    });
  }

  updateState((state) => {
    const rs = getRepoState(state, repo);
    rs.headSha = sha;
    rs.branch = branch;
    rs.status = "queued";
    rs.lastError = null;
    recordActivity(state, {
      type: "triggered",
      repo,
      sha,
      shortSha: sha.slice(0, 7),
      message: `queued ${target.label}`,
    });
    return state;
  });

  const pid = spawnBackgroundDeploy(repo, sha);
  if (!pid) {
    updateState((state) => {
      const rs = getRepoState(state, repo);
      rs.status = "idle";
      rs.lastError = "failed to spawn deploy-runner";
      recordActivity(state, {
        type: "spawn_failed",
        repo,
        sha,
        shortSha: sha.slice(0, 7),
        message: "could not spawn deploy-runner",
      });
      return state;
    });
    process.exit(1);
  }

  updateState((state) => {
    recordActivity(state, {
      type: "spawned",
      repo,
      sha,
      shortSha: sha.slice(0, 7),
      pid,
      message: `deploy-runner pid ${pid}`,
    });
    return state;
  });
}

main();
