/**
 * Persistent local deployment state (logs/ — gitignored except .gitkeep).
 */
const fs = require("node:fs");
const path = require("node:path");

const { REPO_ROOT } = require("./deploy-config.cjs");

const LOGS_ROOT = path.join(REPO_ROOT, "logs");
const STATE_FILE = path.join(LOGS_ROOT, "deployments.json");

function ensureLogsRoot() {
  fs.mkdirSync(LOGS_ROOT, { recursive: true });
  const gitkeep = path.join(LOGS_ROOT, ".gitkeep");
  if (!fs.existsSync(gitkeep)) {
    fs.writeFileSync(gitkeep, "", "utf8");
  }
}

function defaultState() {
  return {
    version: 1,
    updatedAt: new Date().toISOString(),
    repos: {},
    deployments: [],
    activities: [],
  };
}

const TERMINAL_REPO_STATUSES = new Set(["success", "failure", "cancelled"]);

function isStuckQueued(rs) {
  return rs?.status === "queued" && !rs.pid && !rs.currentDeploymentId;
}

function normalizeRepoStatus(rs) {
  if (!rs) return;
  if (TERMINAL_REPO_STATUSES.has(rs.status)) {
    rs.status = "idle";
  }
  if (isStuckQueued(rs)) {
    rs.status = "idle";
    if (!rs.lastError) {
      rs.lastError = "Deploy never started (stuck queued — run: npm run deploy:retry)";
    }
  }
}

function recordActivity(state, activity) {
  if (!state.activities) state.activities = [];
  state.activities.unshift({
    at: new Date().toISOString(),
    ...activity,
  });
  const max = Number.parseInt(process.env.DISKWise_ACTIVITY_MAX || "80", 10);
  if (state.activities.length > max) {
    state.activities = state.activities.slice(0, max);
  }
}

function isPidAlive(pid) {
  if (!pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function reconcileState(state) {
  let changed = false;

  for (const [repo, rs] of Object.entries(state.repos || {})) {
    if (!rs.lastDeploymentId) {
      const latest = (state.deployments || []).find((d) => d.repo === repo);
      if (latest) {
        rs.lastDeploymentId = latest.id;
        changed = true;
      }
    }

    const before = JSON.stringify(rs);

    if (rs.status === "in_progress" && rs.pid && !isPidAlive(rs.pid)) {
      const finishedAt = new Date().toISOString();
      const deploymentId = rs.currentDeploymentId;
      rs.status = "idle";
      rs.pid = null;
      rs.currentDeploymentId = null;
      if (!rs.lastError) {
        rs.lastError = "deploy process exited unexpectedly";
      }
      if (deploymentId) {
        const dep = findDeployment(state, deploymentId);
        if (dep && dep.status === "in_progress") {
          const durationMs = dep.startedAt
            ? Date.now() - new Date(dep.startedAt).getTime()
            : null;
          upsertDeployment(state, {
            ...dep,
            status: "failure",
            finishedAt,
            durationMs,
            exitCode: dep.exitCode ?? 1,
            pid: null,
          });
          rs.lastDeploymentId = deploymentId;
          recordActivity(state, {
            type: "failure",
            repo: dep.repo,
            deploymentId,
            sha: dep.sha,
            shortSha: dep.shortSha,
            message: rs.lastError,
            logFile: dep.logFile,
          });
        }
      }
    }

    normalizeRepoStatus(rs);
    if (JSON.stringify(rs) !== before) {
      changed = true;
    }
  }

  for (const dep of state.deployments || []) {
    if (dep.status !== "in_progress") continue;
    const rs = state.repos[dep.repo];
    if (!rs || rs.currentDeploymentId !== dep.id) {
      const finishedAt = new Date().toISOString();
      const durationMs = dep.startedAt
        ? Date.now() - new Date(dep.startedAt).getTime()
        : null;
      const message = "deployment orphaned (process no longer tracked)";
      upsertDeployment(state, {
        ...dep,
        status: "failure",
        finishedAt,
        durationMs,
        exitCode: dep.exitCode ?? 1,
        pid: null,
      });
      if (rs) {
        rs.lastDeploymentId = dep.id;
        if (!rs.lastError) rs.lastError = message;
        if (rs.status !== "idle") {
          rs.status = "idle";
          rs.pid = null;
          rs.currentDeploymentId = null;
        }
      }
      recordActivity(state, {
        type: "failure",
        repo: dep.repo,
        deploymentId: dep.id,
        sha: dep.sha,
        shortSha: dep.shortSha,
        message,
        logFile: dep.logFile,
      });
      changed = true;
    }
  }

  return changed;
}

function readState() {
  ensureLogsRoot();
  if (!fs.existsSync(STATE_FILE)) {
    return defaultState();
  }
  try {
    const data = JSON.parse(fs.readFileSync(STATE_FILE, "utf8"));
    const state = {
      ...defaultState(),
      ...data,
      repos: data.repos || {},
      deployments: data.deployments || [],
      activities: data.activities || [],
    };
    if (reconcileState(state)) {
      return writeState(state);
    }
    return state;
  } catch {
    return defaultState();
  }
}

function writeState(state) {
  ensureLogsRoot();
  const next = { ...state, updatedAt: new Date().toISOString() };
  const tmp = `${STATE_FILE}.tmp`;
  fs.writeFileSync(tmp, `${JSON.stringify(next, null, 2)}\n`, "utf8");
  fs.renameSync(tmp, STATE_FILE);
  return next;
}

function updateState(mutator) {
  const state = readState();
  const next = mutator(state) || state;
  return writeState(next);
}

function repoLogDir(repo) {
  const dir = path.join(LOGS_ROOT, repo);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function makeDeploymentId(repo, sha) {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const short = (sha || "unknown").slice(0, 7);
  return `${repo}-${stamp}-${short}`;
}

function logFileForDeployment(repo, deploymentId) {
  return path.join(repoLogDir(repo), `${deploymentId}.log`);
}

function relativeLogPath(absolutePath) {
  return path.relative(REPO_ROOT, absolutePath);
}

function absoluteLogPath(relativeOrAbsolute) {
  if (path.isAbsolute(relativeOrAbsolute)) {
    return relativeOrAbsolute;
  }
  return path.join(REPO_ROOT, relativeOrAbsolute);
}

function getRepoState(state, repo) {
  if (!state.repos[repo]) {
    state.repos[repo] = {
      branch: "main",
      headSha: null,
      lastDeployedSha: null,
      status: "idle",
      currentDeploymentId: null,
      lastDeploymentId: null,
      lastError: null,
      pid: null,
    };
  }
  return state.repos[repo];
}

function findDeployment(state, id) {
  return state.deployments.find((d) => d.id === id) || null;
}

function upsertDeployment(state, deployment) {
  const idx = state.deployments.findIndex((d) => d.id === deployment.id);
  if (idx === -1) {
    state.deployments.unshift(deployment);
  } else {
    state.deployments[idx] = { ...state.deployments[idx], ...deployment };
  }
  const max = Number.parseInt(process.env.DISKWise_DEPLOY_HISTORY_MAX || "100", 10);
  if (state.deployments.length > max) {
    state.deployments = state.deployments.slice(0, max);
  }
}

module.exports = {
  REPO_ROOT,
  LOGS_ROOT,
  STATE_FILE,
  ensureLogsRoot,
  readState,
  writeState,
  updateState,
  repoLogDir,
  makeDeploymentId,
  logFileForDeployment,
  relativeLogPath,
  absoluteLogPath,
  getRepoState,
  findDeployment,
  upsertDeployment,
  isStuckQueued,
  recordActivity,
};
