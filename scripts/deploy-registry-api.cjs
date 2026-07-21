/**
 * Deploy the DiskWise registry API to Cloud Run from a GHCR image
 * and ensure Firestore indexes exist.
 *
 * Builds/pushes via suherman-net-infra `ghcr-cloudrun-deploy` helper
 * (ghcr.io/iman-suherman/diskwise-registry-api:<sha>).
 */
const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
const { getDeployTarget } = require("./deploy-config.cjs");
const { recordDirectDeployOutcome } = require("./deploy-record-direct.cjs");

const root = path.join(__dirname, "..");
const serviceDir = path.join(root, "services", "registry-api");
const shell = process.platform === "win32";
let gcpEnv = process.env;
const DEPLOY_REPO = "diskwise-registry";
const DEPLOY_NPM_SCRIPT = "deploy:registry";
const deployTarget = getDeployTarget(DEPLOY_REPO);
const deployStartedAt = new Date().toISOString();

function recordDeploy(status, { exitCode = 0, error = null } = {}) {
  recordDirectDeployOutcome({
    repo: DEPLOY_REPO,
    label: deployTarget?.label,
    npmScript: DEPLOY_NPM_SCRIPT,
    status,
    startedAt: deployStartedAt,
    exitCode,
    error,
  });
}

function fail(message) {
  recordDeploy("failure", { exitCode: 1, error: message });
  console.error(`deploy:registry: ${message}`);
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

function main() {
  gcpEnv = applyGcpEnv(root);

  const projectId = resolveGcpProjectId(root);
  if (!projectId) fail("GCP_PROJECT_ID is not set. Run: npm run login");

  const region = process.env.GCP_LOCATION?.trim() || "australia-southeast1";
  const serviceName = process.env.REGISTRY_API_SERVICE?.trim() || "diskwise-registry-api";
  const collection = process.env.FIRESTORE_APP_COLLECTION?.trim() || "app_versions";
  const catalog = process.env.FIRESTORE_APP_CATALOG?.trim() || "app_catalog";
  const downloadBase =
    process.env.PUBLIC_DOWNLOAD_BASE_URL?.trim() ||
    "https://diskwise-download.suherman.net/downloads";
  const defaultAppId = process.env.DEFAULT_APP_ID?.trim() || "diskwise-macos";
  const gcsBucket = process.env.GCS_APP_BUCKET?.trim() || `${projectId}-diskwise`;
  const gcsPrefix = process.env.GCS_APP_PREFIX?.trim() || "releases";
  const registryApiPublicUrl =
    process.env.REGISTRY_API_PUBLIC_URL?.trim() ||
    process.env.NEXT_PUBLIC_REGISTRY_API_URL?.trim() ||
    "https://diskwise-registry.suherman.net";

  const indexesPath = path.join(root, "firestore", "indexes.json");
  if (fs.existsSync(indexesPath)) {
    console.log("deploy:registry: ensuring Firestore composite index…");
    const indexResult = spawnSync(
      "gcloud",
      [
        "firestore",
        "indexes",
        "composite",
        "create",
        "--collection-group",
        collection,
        "--query-scope",
        "COLLECTION",
        "--field-config",
        "field-path=pluginId,order=ASCENDING",
        "--field-config",
        "field-path=versionSortKey,order=DESCENDING",
        "--project",
        projectId,
        "--database=(default)",
        "--quiet",
      ],
      { cwd: root, shell, env: process.env, encoding: "utf8" },
    );
    if (indexResult.status === 0) {
      console.log("deploy:registry: Firestore index created or already exists");
    } else {
      console.warn(
        "deploy:registry: Firestore index step skipped — create manually from firestore/indexes.json if queries fail",
      );
    }
  }

  const { buildAndPushImage } = requireGhcrDeploy();
  let image;
  try {
    image = buildAndPushImage({
      cwd: root,
      contextDir: serviceDir,
      imageName: "diskwise-registry-api",
      logPrefix: "deploy:registry",
    });
  } catch (error) {
    fail(error.message || String(error));
  }

  console.log(`deploy:registry: deploying ${serviceName} ← ${image} (${region})…`);
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
    "--set-env-vars",
    `GCP_PROJECT_ID=${projectId},FIRESTORE_APP_COLLECTION=${collection},FIRESTORE_APP_CATALOG=${catalog},PUBLIC_DOWNLOAD_BASE_URL=${downloadBase},DEFAULT_APP_ID=${defaultAppId},GCS_APP_BUCKET=${gcsBucket},GCS_APP_PREFIX=${gcsPrefix},REGISTRY_API_PUBLIC_URL=${registryApiPublicUrl}`,
  ]);

  console.log("deploy:registry: done");
  recordDeploy("success", { exitCode: 0 });
}

main();
