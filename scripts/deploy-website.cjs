/**
 * Deploy the Next.js marketing website to Cloud Run.
 */
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const { getProjectAdcPath } = require("./gcp-lib-adc.cjs");
const { loadDotenv } = require("./load-dotenv.cjs");
const { getDeployTarget } = require("./deploy-config.cjs");
const { recordDirectDeployOutcome } = require("./deploy-record-direct.cjs");
const { readState, getRepoState } = require("./deploy-store.cjs");
const {
  requiresWebsiteDeploy,
  changedFilesSince,
} = require("./deploy-change-filter.cjs");

const root = path.join(__dirname, "..");
const websiteDir = path.join(root, "website");
const shell = process.platform === "win32";
const DEPLOY_REPO = "diskwise-website";
const DEPLOY_NPM_SCRIPT = "deploy:website";
const deployTarget = getDeployTarget(DEPLOY_REPO);
const deployStartedAt = new Date().toISOString();

function recordDeploy(status, { exitCode = 0, error = null, activityMessage = null } = {}) {
  recordDirectDeployOutcome({
    repo: DEPLOY_REPO,
    label: deployTarget?.label,
    npmScript: DEPLOY_NPM_SCRIPT,
    status,
    startedAt: deployStartedAt,
    exitCode,
    error,
    activityMessage,
  });
}

function fail(message) {
  recordDeploy("failure", { exitCode: 1, error: message });
  console.error(`deploy:website: ${message}`);
  process.exit(1);
}

function applyGcpEnv() {
  loadDotenv(root);
  const projectAdc = getProjectAdcPath(root);
  if (fs.existsSync(projectAdc)) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = projectAdc;
  }
}

function run(command, args, options = {}) {
  const r = spawnSync(command, args, {
    stdio: "inherit",
    cwd: options.cwd || root,
    shell,
    env: process.env,
  });
  if (r.error) throw r.error;
  if (r.status !== 0) {
    recordDeploy("failure", { exitCode: r.status ?? 1, error: `${command} exited ${r.status ?? 1}` });
    process.exit(r.status ?? 1);
  }
}

function gitHead() {
  const r = spawnSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : null;
}

function maybeSkipNonWebsiteDeploy() {
  const head = gitHead();
  if (!head) return false;

  const state = readState();
  const rs = getRepoState(state, DEPLOY_REPO);
  const lastDeployed = rs.lastDeployedSha;
  if (!lastDeployed || lastDeployed === head) return false;

  const files = changedFilesSince(lastDeployed, head);
  if (requiresWebsiteDeploy(files)) return false;

  const message = "deploy synced at HEAD — no website changes since last deploy";
  console.log(`deploy:website: skip — ${message}`);
  recordDeploy("success", { exitCode: 0, activityMessage: message });
  process.exit(0);
}

function main() {
  applyGcpEnv();
  maybeSkipNonWebsiteDeploy();

  const projectId = resolveGcpProjectId(root);
  if (!projectId) fail("GCP_PROJECT_ID is not set. Run: npm run login");

  const region = process.env.GCP_LOCATION?.trim() || "australia-southeast1";
  const serviceName = process.env.WEBSITE_SERVICE?.trim() || "diskwise-website";
  const registryApiUrl =
    process.env.NEXT_PUBLIC_REGISTRY_API_URL?.trim() ||
    "https://diskwise-registry.suherman.net";
  // Always bake production CDN URLs into the website — never SPARKLE_LOCAL / localhost.
  const downloadBase =
    process.env.PUBLIC_DOWNLOAD_BASE_URL?.trim() ||
    process.env.NEXT_PUBLIC_DOWNLOAD_BASE_URL?.trim() ||
    "https://diskwise-download.suherman.net/downloads";

  console.log(`deploy:website: deploying ${serviceName} to Cloud Run (${region})…`);
  run("gcloud", [
    "run",
    "deploy",
    serviceName,
    "--source",
    websiteDir,
    "--project",
    projectId,
    "--region",
    region,
    "--allow-unauthenticated",
    "--quiet",
    "--set-build-env-vars",
    `NEXT_PUBLIC_REGISTRY_API_URL=${registryApiUrl},NEXT_PUBLIC_APP_ID=diskwise-macos,NEXT_PUBLIC_DOWNLOAD_BASE_URL=${downloadBase}`,
  ]);

  console.log("deploy:website: done");
  recordDeploy("success", { exitCode: 0 });
}

main();
