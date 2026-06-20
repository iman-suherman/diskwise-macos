/**
 * Record deploy outcome when deploy scripts run outside deploy-runner.
 */
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const { REPO_ROOT } = require("./deploy-config.cjs");
const {
  updateState,
  getRepoState,
  makeDeploymentId,
  logFileForDeployment,
  relativeLogPath,
  upsertDeployment,
  recordActivity,
} = require("./deploy-store.cjs");

const RUNNER_ENV = "SUHERMAN_DEPLOY_RUNNER";

function isRunnerChild() {
  return process.env[RUNNER_ENV] === "1";
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

function recordDirectDeployOutcome({
  repo,
  label,
  npmScript,
  status,
  startedAt,
  exitCode = 0,
  error = null,
  activityMessage = null,
}) {
  if (isRunnerChild()) return;

  const sha = gitHead();
  if (!sha) return;

  const branch = gitBranch();
  const finishedAt = new Date().toISOString();
  const durationMs = startedAt ? Date.now() - new Date(startedAt).getTime() : null;
  const deploymentId = makeDeploymentId(repo, sha);
  const logFile = logFileForDeployment(repo, deploymentId);
  const relLog = relativeLogPath(logFile);

  fs.writeFileSync(
    logFile,
    [
      `# Direct deploy ${deploymentId}`,
      `# Target: ${repo}${label ? ` (${label})` : ""}`,
      `# Command: npm run ${npmScript || "deploy"}`,
      `# Started: ${startedAt || finishedAt}`,
      `# Finished: ${finishedAt}`,
      `# Exit code: ${exitCode}`,
      error ? `# Error: ${error}` : "",
      status === "success"
        ? activityMessage || "deploy: done"
        : `deploy: failed (${error || exitCode})`,
    ]
      .filter(Boolean)
      .join("\n") + "\n",
    "utf8",
  );

  updateState((state) => {
    const rs = getRepoState(state, repo);
    rs.branch = branch;
    rs.headSha = sha;
    rs.status = "idle";
    rs.currentDeploymentId = null;
    rs.pid = null;
    rs.lastDeploymentId = deploymentId;
    rs.lastDeployedSha = status === "success" ? sha : rs.lastDeployedSha;
    rs.lastError = status === "success" ? null : error || `exit ${exitCode}`;
    upsertDeployment(state, {
      id: deploymentId,
      repo,
      label: label || repo,
      sha,
      shortSha: sha.slice(0, 7),
      branch,
      status,
      startedAt: startedAt || finishedAt,
      finishedAt,
      durationMs,
      logFile: relLog,
      exitCode,
      npmScript: npmScript || null,
      pid: null,
      direct: true,
    });
    recordActivity(state, {
      type: status,
      repo,
      deploymentId,
      sha,
      shortSha: sha.slice(0, 7),
      durationMs,
      logFile: relLog,
      exitCode,
      message:
        activityMessage ||
        (status === "success"
          ? `deployed in ${durationMs != null ? Math.round(durationMs / 1000) : "?"}s (direct)`
          : error || `exit ${exitCode}`),
    });
    return state;
  });
}

module.exports = {
  RUNNER_ENV,
  recordDirectDeployOutcome,
};
