/**
 * Deploy the Next.js marketing website to Cloud Run.
 *
 * Default: Cloud Build → Artifact Registry (australia-southeast1/cloudrun),
 * then `gcloud run deploy`. This avoids flaky local Podman/QEMU amd64 builds.
 *
 * Optional: WEBSITE_DEPLOY_VIA=ghcr uses suherman-net-infra GHCR helper instead.
 * NEXT_PUBLIC_* defaults are baked in the Dockerfile ARGs.
 */
const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
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
let gcpEnv = process.env;
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

function requireGhcrDeploy() {
  const candidates = [
    process.env.SUHERMAN_NET_INFRA_ROOT?.trim(),
    path.join(os.homedir(), "src", "personal", "suherman-net-infra"),
  ].filter(Boolean);
  for (const infraRoot of candidates) {
    const helper = path.join(infraRoot, "scripts", "lib", "ghcr-cloudrun-deploy.cjs");
    if (fs.existsSync(helper)) return require(helper);
  }
  fail(
    "suherman-net-infra not found. Set SUHERMAN_NET_INFRA_ROOT or clone to ~/src/personal/suherman-net-infra",
  );
}

function run(command, args, options = {}) {
  const r = spawnSync(command, args, {
    stdio: "inherit",
    cwd: options.cwd || root,
    shell,
    env: gcpEnv,
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

function gitShort() {
  const head = gitHead();
  return head ? head.slice(0, 7) : "local";
}

function maybeSkipNonWebsiteDeploy() {
  if (process.env.WEBSITE_FORCE_DEPLOY === "1") return false;

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

function stamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  return (
    `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}` +
    `${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`
  );
}

/** Cloud Build → Artifact Registry (proven path for personal-suherman). */
function buildViaCloudBuild(projectId, region) {
  const repo =
    process.env.WEBSITE_AR_REPO?.trim() ||
    `${region}-docker.pkg.dev/${projectId}/cloudrun/diskwise-website`;
  const tag = process.env.WEBSITE_IMAGE_TAG?.trim() || `${gitShort()}-${stamp()}`;
  const image = `${repo}:${tag}`;

  console.log(`deploy:website: Cloud Build amd64 → ${image}`);
  run(
    "gcloud",
    [
      "builds",
      "submit",
      "--project",
      projectId,
      "--tag",
      image,
      "--timeout",
      process.env.WEBSITE_BUILD_TIMEOUT?.trim() || "1200s",
      "--quiet",
      ".",
    ],
    { cwd: websiteDir },
  );
  return image;
}

function buildViaGhcr(registryApiUrl, downloadBase) {
  const platform = process.env.GHCR_PLATFORM?.trim() || undefined;
  const { buildAndPushImage } = requireGhcrDeploy();
  try {
    return buildAndPushImage({
      cwd: root,
      contextDir: websiteDir,
      imageName: "diskwise-website",
      platform,
      buildArgs: {
        NEXT_PUBLIC_REGISTRY_API_URL: registryApiUrl,
        NEXT_PUBLIC_APP_ID: "diskwise-macos",
        NEXT_PUBLIC_DOWNLOAD_BASE_URL: downloadBase,
      },
      logPrefix: "deploy:website",
    });
  } catch (error) {
    fail(error.message || String(error));
  }
}

function main() {
  gcpEnv = applyGcpEnv(root);
  maybeSkipNonWebsiteDeploy();

  const projectId = resolveGcpProjectId(root);
  if (!projectId) fail("GCP_PROJECT_ID is not set. Run: npm run login");

  const region = process.env.GCP_LOCATION?.trim() || "australia-southeast1";
  const serviceName = process.env.WEBSITE_SERVICE?.trim() || "diskwise-website";
  const registryApiUrl =
    process.env.NEXT_PUBLIC_REGISTRY_API_URL?.trim() ||
    "https://diskwise-registry.suherman.net";
  const downloadBase =
    process.env.PUBLIC_DOWNLOAD_BASE_URL?.trim() ||
    process.env.NEXT_PUBLIC_DOWNLOAD_BASE_URL?.trim() ||
    "https://diskwise-download.suherman.net/downloads";

  const via = (process.env.WEBSITE_DEPLOY_VIA || "cloudbuild").trim().toLowerCase();
  const image =
    via === "ghcr"
      ? buildViaGhcr(registryApiUrl, downloadBase)
      : buildViaCloudBuild(projectId, region);

  console.log(`deploy:website: deploying ${serviceName} ← ${image} (${region})…`);
  run("gcloud", [
    "run",
    "deploy",
    serviceName,
    "--image",
    image,
    "--project",
    projectId,
    "--region",
    region,
    "--allow-unauthenticated",
    "--quiet",
    "--clear-secrets",
  ]);

  console.log("deploy:website: done");
  recordDeploy("success", {
    exitCode: 0,
    activityMessage: `Cloud Build amd64 + Cloud Run deploy — ${gitShort()}`,
  });
}

main();
