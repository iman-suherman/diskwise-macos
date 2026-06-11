/**
 * Deploy the registry API to Cloud Run and ensure Firestore indexes exist.
 */
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
const { loadDotenv } = require("./load-dotenv.cjs");

const root = path.join(__dirname, "..");
const serviceDir = path.join(root, "services", "registry-api");
const shell = process.platform === "win32";

function fail(message) {
  console.error(`deploy:registry: ${message}`);
  process.exit(1);
}

function run(command, args, options = {}) {
  const r = spawnSync(command, args, {
    stdio: "inherit",
    cwd: options.cwd || root,
    shell,
    env: process.env,
  });
  if (r.error) throw r.error;
  if (r.status !== 0) process.exit(r.status ?? 1);
}

function main() {
  loadDotenv(root);
  applyGcpEnv(root);

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
      { cwd: root, shell, env: process.env, encoding: "utf8" }
    );
    if (indexResult.status === 0) {
      console.log("deploy:registry: Firestore index created or already exists");
    } else {
      console.warn(
        "deploy:registry: Firestore index step skipped — create manually from firestore/indexes.json if queries fail"
      );
    }
  }

  console.log(`deploy:registry: deploying ${serviceName} to Cloud Run (${region})…`);
  run("gcloud", [
    "run",
    "deploy",
    serviceName,
    "--source",
    serviceDir,
    "--project",
    projectId,
    "--region",
    region,
    "--allow-unauthenticated",
    "--quiet",
    "--set-env-vars",
    `GCP_PROJECT_ID=${projectId},FIRESTORE_APP_COLLECTION=${collection},FIRESTORE_APP_CATALOG=${catalog},PUBLIC_DOWNLOAD_BASE_URL=${downloadBase},DEFAULT_APP_ID=${defaultAppId}`,
  ]);

  console.log("deploy:registry: done");
}

main();
