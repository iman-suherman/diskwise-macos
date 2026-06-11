#!/usr/bin/env node
/**
 * Interrupt a running local website deployment.
 */
const { DEPLOY_TARGETS } = require("./deploy-config.cjs");
const {
  readState,
  updateState,
  getRepoState,
  findDeployment,
  upsertDeployment,
  recordActivity,
} = require("./deploy-store.cjs");

function parseArgs(argv) {
  let repo = null;
  let all = false;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--repo" && argv[i + 1]) repo = argv[++i];
    else if (argv[i] === "--all") all = true;
    else if (argv[i] === "-h" || argv[i] === "--help") {
      console.log(`Usage: npm run deploy:stop -- --repo diskwise-website | --all`);
      process.exit(0);
    }
  }
  if (!repo && !all) {
    console.error("error: specify --repo <name> or --all");
    process.exit(1);
  }
  return { repo, all };
}

async function stopRepo(repo) {
  const state = readState();
  const rs = state.repos[repo];
  if (!rs || (rs.status !== "in_progress" && rs.status !== "queued")) {
    console.log(`${repo}: not running`);
    return false;
  }

  let killed = false;
  if (rs.pid) {
    try {
      process.kill(rs.pid, "SIGTERM");
      killed = true;
    } catch {
      killed = false;
    }
  }

  const deploymentId = rs.currentDeploymentId;
  const finishedAt = new Date().toISOString();

  updateState((s) => {
    const r = getRepoState(s, repo);
    r.status = "idle";
    r.pid = null;
    r.lastError = null;
    if (deploymentId) {
      const dep = findDeployment(s, deploymentId);
      upsertDeployment(s, {
        ...(dep || { id: deploymentId, repo }),
        status: "cancelled",
        finishedAt,
        exitCode: 130,
        signal: "SIGTERM",
      });
      r.lastDeploymentId = deploymentId;
    }
    r.currentDeploymentId = null;
    recordActivity(s, {
      type: "cancelled",
      repo,
      deploymentId,
      pid: rs.pid,
      message: killed ? "stopped via SIGTERM" : "marked cancelled (no pid)",
    });
    return s;
  });

  console.log(`${repo}: ${killed ? "stopped" : "marked cancelled"} (pid ${rs.pid || "—"})`);
  return true;
}

async function main() {
  const { repo, all } = parseArgs(process.argv.slice(2));
  const targets = all
    ? DEPLOY_TARGETS.filter((t) => t.npmScript).map((t) => t.repo)
    : [repo];

  let count = 0;
  for (const name of targets) {
    if (await stopRepo(name)) count += 1;
  }
  console.log(`Interrupted ${count} deployment(s).`);
}

main().catch((err) => {
  console.error(`deploy-stop: ${err.message || err}`);
  process.exit(1);
});
