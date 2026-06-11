#!/usr/bin/env node
/**
 * Run a tracked local website deploy; write logs to logs/<target>/.
 *
 * Usage:
 *   node scripts/deploy-runner.cjs --repo diskwise-website [--sha <commit>] [--background]
 */

const fs = require("node:fs");
const { spawn, spawnSync } = require("node:child_process");
const { REPO_ROOT, getDeployTarget } = require("./deploy-config.cjs");
const {
  readState,
  updateState,
  getRepoState,
  makeDeploymentId,
  logFileForDeployment,
  relativeLogPath,
  upsertDeployment,
  findDeployment,
  recordActivity,
} = require("./deploy-store.cjs");
const { loadDotenv } = require("./load-dotenv.cjs");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const { getProjectAdcPath } = require("./gcp-lib-adc.cjs");

const shell = process.platform === "win32";

function parseArgs(argv) {
  let repo = null;
  let sha = null;
  let background = false;

  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--repo" && argv[i + 1]) repo = argv[++i];
    else if (argv[i] === "--sha" && argv[i + 1]) sha = argv[++i];
    else if (argv[i] === "--background") background = true;
    else if (argv[i] === "-h" || argv[i] === "--help") {
      console.log(
        "Usage: node scripts/deploy-runner.cjs --repo diskwise-website [--sha <commit>] [--background]",
      );
      process.exit(0);
    }
  }

  if (!repo) {
    console.error("error: --repo is required");
    process.exit(1);
  }
  return { repo, sha, background };
}

function gitHead() {
  const result = spawnSync("git", ["rev-parse", "HEAD"], {
    cwd: REPO_ROOT,
    encoding: "utf8",
  });
  if (result.status !== 0) return null;
  return result.stdout.trim();
}

function gitBranch() {
  const result = spawnSync("git", ["rev-parse", "--abbrev-ref", "HEAD"], {
    cwd: REPO_ROOT,
    encoding: "utf8",
  });
  if (result.status !== 0) return "main";
  return result.stdout.trim() || "main";
}

function isDeployConfigured() {
  loadDotenv(REPO_ROOT);
  const projectId = resolveGcpProjectId(REPO_ROOT);
  if (!projectId) return false;
  return fs.existsSync(getProjectAdcPath(REPO_ROOT));
}

function logMsg(background, msg) {
  if (!background) {
    console.log(msg);
  }
}

function abortEarly(repo, sha, reason, background) {
  updateState((state) => {
    const rs = getRepoState(state, repo);
    rs.status = "idle";
    rs.currentDeploymentId = null;
    rs.pid = null;
    rs.lastError = reason;
    recordActivity(state, {
      type: "failure",
      repo,
      sha,
      shortSha: sha ? sha.slice(0, 7) : null,
      message: reason,
    });
    return state;
  });
  if (!background) {
    console.error(`error: ${reason}`);
  }
  process.exit(1);
}

function runDeploy(target, logFile, deploymentId, background) {
  return new Promise((resolve) => {
    const header = [
      `# Deployment ${deploymentId}`,
      `# Target: ${target.repo} (${target.label})`,
      `# Command: npm run ${target.npmScript}`,
      `# Started: ${new Date().toISOString()}`,
      "",
    ].join("\n");
    fs.writeFileSync(logFile, header, "utf8");

    const child = spawn("npm", ["run", target.npmScript], {
      cwd: REPO_ROOT,
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
      shell,
    });

    if (child.pid) {
      updateState((state) => {
        const rs = getRepoState(state, target.repo);
        rs.pid = child.pid;
        rs.status = "in_progress";
        const dep = findDeployment(state, deploymentId);
        if (dep) dep.pid = child.pid;
        return state;
      });
    }

    const append = (chunk) => {
      fs.appendFileSync(logFile, chunk);
      if (!background) process.stdout.write(chunk);
    };

    child.stdout.on("data", append);
    child.stderr.on("data", append);

    child.on("close", (code, signal) => {
      const footer = [
        "",
        `# Finished: ${new Date().toISOString()}`,
        signal ? `# Signal: ${signal}` : "",
        `# Exit code: ${code ?? 1}`,
      ]
        .filter(Boolean)
        .join("\n");
      fs.appendFileSync(logFile, `${footer}\n`);
      resolve({ code: code ?? 1, signal });
    });

    child.on("error", (err) => {
      fs.appendFileSync(logFile, `\n# Spawn error: ${err.message}\n`);
      resolve({ code: 1, signal: null });
    });
  });
}

function finishDeploy({
  repo,
  target,
  sha,
  branch,
  deploymentId,
  relLog,
  startedAt,
  exitCode,
  signal,
  background,
}) {
  const finishedAt = new Date().toISOString();
  const durationMs = Date.now() - new Date(startedAt).getTime();
  let status = exitCode === 0 ? "success" : "failure";
  if (signal === "SIGTERM" || signal === "SIGKILL" || exitCode === 130) {
    status = "cancelled";
  }

  const prior = readState();
  const wasCancelled =
    prior.deployments.find((d) => d.id === deploymentId)?.status === "cancelled";
  if (wasCancelled) {
    status = "cancelled";
  }

  updateState((state) => {
    const rs = getRepoState(state, repo);
    rs.status = "idle";
    rs.currentDeploymentId = null;
    rs.pid = null;
    rs.lastDeploymentId = deploymentId;
    rs.lastDeployedSha = status === "success" ? sha : rs.lastDeployedSha;
    rs.lastError =
      status === "success" ? null : status === "cancelled" ? null : `exit ${exitCode}`;
    upsertDeployment(state, {
      id: deploymentId,
      repo,
      label: target.label,
      sha,
      shortSha: sha.slice(0, 7),
      branch,
      status,
      startedAt,
      finishedAt,
      durationMs,
      logFile: relLog,
      exitCode,
      signal,
      npmScript: target.npmScript,
      pid: null,
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
      signal,
      message:
        status === "success"
          ? `deployed in ${Math.round(durationMs / 1000)}s`
          : status === "cancelled"
            ? "deploy cancelled"
            : `exit ${exitCode}`,
    });
    return state;
  });

  if (!background) {
    if (status === "success") {
      console.log(
        `Deploy succeeded for ${repo} in ${Math.round(durationMs / 1000)}s. Log: ${relLog}`,
      );
    } else if (status === "cancelled") {
      console.error(`Deploy cancelled for ${repo}. Log: ${relLog}`);
    } else {
      console.error(`Deploy failed for ${repo} (exit ${exitCode}). Log: ${relLog}`);
    }
  }
  return status;
}

async function main() {
  const { repo, sha: shaArg, background } = parseArgs(process.argv.slice(2));
  const target = getDeployTarget(repo);

  const branch = gitBranch();
  const sha = shaArg || gitHead();

  if (!target) {
    abortEarly(repo, sha, `unknown target ${repo}`, background);
  }
  if (!target.npmScript) {
    abortEarly(repo, sha, `${repo} has no auto-deploy`, background);
  }
  if (!isDeployConfigured()) {
    abortEarly(repo, sha, "GCP not configured (run: npm run login)", background);
  }
  if (!sha) {
    abortEarly(repo, null, "could not resolve HEAD", background);
  }

  const existing = readState();
  const rsExisting = getRepoState(existing, repo);
  if (rsExisting.status === "in_progress") {
    if (!background) {
      console.log(`deploy-runner: skip — ${repo} already in progress`);
    }
    process.exit(0);
  }

  const deploymentId = makeDeploymentId(repo, sha);
  const logFile = logFileForDeployment(repo, deploymentId);
  const relLog = relativeLogPath(logFile);
  const startedAt = new Date().toISOString();

  updateState((state) => {
    const rs = getRepoState(state, repo);
    rs.branch = branch;
    rs.headSha = sha;
    rs.status = "in_progress";
    rs.currentDeploymentId = deploymentId;
    rs.lastError = null;
    rs.pid = null;
    recordActivity(state, {
      type: "started",
      repo,
      deploymentId,
      sha,
      shortSha: sha.slice(0, 7),
      message: `npm run ${target.npmScript}`,
    });
    upsertDeployment(state, {
      id: deploymentId,
      repo,
      label: target.label,
      sha,
      shortSha: sha.slice(0, 7),
      branch,
      status: "in_progress",
      startedAt,
      finishedAt: null,
      durationMs: null,
      logFile: relLog,
      exitCode: null,
      npmScript: target.npmScript,
      pid: null,
    });
    return state;
  });

  logMsg(background, `Deploying ${target.label} @ ${sha.slice(0, 7)} → ${relLog}`);

  const { code, signal } = await runDeploy(target, logFile, deploymentId, background);
  const status = finishDeploy({
    repo,
    target,
    sha,
    branch,
    deploymentId,
    relLog,
    startedAt,
    exitCode: code,
    signal,
    background,
  });

  if (status !== "success" && !background) {
    process.exit(code || 1);
  }
}

main().catch((err) => {
  console.error(`deploy-runner: ${err.message || err}`);
  process.exit(1);
});
