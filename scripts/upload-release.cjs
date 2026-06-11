/**
 * Upload the packaged DMG to Google Cloud Storage,
 * generate semver release notes, and register the version in Firestore.
 */
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const { assertSemver } = require("./semver.cjs");
const { generateReleaseNotes, writeReleaseArtifacts } = require("./generate-release-notes.cjs");
const { registerPluginVersion } = require("./register-version.cjs");
const { generateAppcast } = require("./generate-appcast.cjs");
const {
  sparkleZipFileName,
  publicSparkleDownloadUrl,
  resolveDownloadBase,
} = require("./public-download-url.cjs");

const root = path.join(__dirname, "..");
const shell = process.platform === "win32";

function fail(message) {
  console.error(`upload: ${message}`);
  process.exit(1);
}

function run(command, args) {
  const r = spawnSync(command, args, {
    stdio: "inherit",
    cwd: root,
    shell,
    env: process.env,
    encoding: "utf8",
  });

  if (r.error) throw r.error;
  if (r.status !== 0) process.exit(r.status ?? 1);
  return r;
}

function resolveAppId(packageJson) {
  return process.env.DEFAULT_APP_ID?.trim() || packageJson.name;
}

function resolveBucket(projectId) {
  const configured = process.env.GCS_APP_BUCKET?.trim();
  if (configured) return configured;
  return `${projectId}-diskwise`;
}

function resolveLocation() {
  return process.env.GCS_LOCATION?.trim() || "australia-southeast1";
}

function resolvePrefix() {
  const prefix = process.env.GCS_APP_PREFIX?.trim() || "releases";
  return prefix.replace(/^\/+|\/+$/g, "");
}

function resolveReleasesDir() {
  return path.join(root, "releases");
}

function dmgFileName(appId, version) {
  return `${appId}-${version}.dmg`;
}

function resolveDmgPath(options) {
  if (options.dmgPath && fs.existsSync(options.dmgPath)) {
    return options.dmgPath;
  }

  const packageJson = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
  const version = options.version || packageJson.version;
  const appId = resolveAppId(packageJson);
  const versionedPath = path.join(resolveReleasesDir(), dmgFileName(appId, version));
  if (fs.existsSync(versionedPath)) return versionedPath;

  const defaultPath = path.join(root, "DiskWise.dmg");
  if (fs.existsSync(defaultPath)) return defaultPath;

  fail(`DMG not found. Expected ${versionedPath} or ${defaultPath}`);
}

function bucketExists(bucket, projectId) {
  const r = spawnSync(
    "gcloud",
    [
      "storage",
      "buckets",
      "describe",
      `gs://${bucket}`,
      "--project",
      projectId,
      "--format=value(name)",
    ],
    { cwd: root, shell, env: process.env, encoding: "utf8" }
  );
  return r.status === 0;
}

function ensureBucket(bucket, projectId, location) {
  if (bucketExists(bucket, projectId)) {
    console.log(`upload: using bucket gs://${bucket}`);
    return;
  }

  console.log(`upload: creating bucket gs://${bucket} (${location})…`);
  run("gcloud", [
    "storage",
    "buckets",
    "create",
    `gs://${bucket}`,
    "--project",
    projectId,
    "--location",
    location,
    "--uniform-bucket-level-access",
  ]);
  console.log(`upload: created bucket gs://${bucket}`);
}

async function uploadRelease(options = {}) {
  applyGcpEnv(root);

  const projectId = resolveGcpProjectId(root);
  if (!projectId) {
    fail("GCP_PROJECT_ID is not set. Run: npm run login");
  }

  const packageJson = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
  const version = options.version || packageJson.version;
  assertSemver(version, "package.json version");
  const appId = resolveAppId(packageJson);

  const previousLabel = options.previousVersion
    ? `v${options.previousVersion}`
    : options.sinceCommit?.slice(0, 7);

  const release = generateReleaseNotes({
    version,
    sinceCommit: options.sinceCommit || null,
    previousLabel,
    pluginId: appId,
  });
  const artifacts = writeReleaseArtifacts(release);
  console.log(`upload: release notes → ${artifacts.jsonPath}`);
  console.log(`upload: ${release.summary}`);

  const sparkleZipPath = path.join(
    resolveReleasesDir(),
    "sparkle",
    sparkleZipFileName(version)
  );
  if (!fs.existsSync(sparkleZipPath)) {
    const appPath =
      options.appPath ||
      path.join(root, ".build/DerivedData/Build/Products/Release/DiskWise.app");
    if (fs.existsSync(appPath)) {
      console.log("upload: creating Sparkle ZIP archive…");
      run("bash", ["scripts/package-zip.sh", appPath, version, sparkleZipPath]);
    } else {
      console.warn(`upload: Sparkle ZIP not found (${sparkleZipPath}); skipping Sparkle upload`);
    }
  }

  let appcastPath = path.join(root, "website", "public", "appcast.xml");
  if (fs.existsSync(sparkleZipPath)) {
    const appcastArtifacts = generateAppcast({
      release,
      downloadBase: resolveDownloadBase({ ...process.env, SPARKLE_LOCAL: "0", LOCAL_RELEASE: "0" }),
    });
    appcastPath = appcastArtifacts.websiteAppcastPath;
    console.log(`upload: Sparkle appcast → ${appcastPath}`);
  }

  const bucket = resolveBucket(projectId);
  const prefix = resolvePrefix();
  const dmgPath = resolveDmgPath(options);
  const dmgName = path.basename(dmgPath);
  const objectPath = `${prefix}/${version}/${dmgName}`;
  const latestObjectPath = `${prefix}/latest/${dmgName}`;
  const sparkleZipName = sparkleZipFileName(version);
  const sparkleObjectPath = `${prefix}/${version}/${sparkleZipName}`;
  const sparkleLatestObjectPath = `${prefix}/latest/${sparkleZipName}`;
  const releaseNotesObjectPath = `${prefix}/${version}/release-${version}.json`;
  const releaseNotesMarkdownPath = `${prefix}/${version}/release-${version}.md`;
  const appcastObjectPath = `${prefix}/appcast.xml`;

  ensureBucket(bucket, projectId, resolveLocation());

  console.log(`upload: uploading ${dmgName} → gs://${bucket}/${objectPath}`);
  run("gcloud", ["storage", "cp", dmgPath, `gs://${bucket}/${objectPath}`, "--project", projectId]);

  console.log(`upload: uploading latest copy → gs://${bucket}/${latestObjectPath}`);
  run("gcloud", [
    "storage",
    "cp",
    dmgPath,
    `gs://${bucket}/${latestObjectPath}`,
    "--project",
    projectId,
  ]);

  console.log(`upload: uploading release notes → gs://${bucket}/${releaseNotesObjectPath}`);
  run("gcloud", [
    "storage",
    "cp",
    artifacts.jsonPath,
    `gs://${bucket}/${releaseNotesObjectPath}`,
    "--project",
    projectId,
  ]);

  run("gcloud", [
    "storage",
    "cp",
    artifacts.mdPath,
    `gs://${bucket}/${releaseNotesMarkdownPath}`,
    "--project",
    projectId,
  ]);

  let sparkleSizeBytes = null;
  if (fs.existsSync(sparkleZipPath)) {
    console.log(`upload: uploading ${sparkleZipName} → gs://${bucket}/${sparkleObjectPath}`);
    run("gcloud", [
      "storage",
      "cp",
      sparkleZipPath,
      `gs://${bucket}/${sparkleObjectPath}`,
      "--project",
      projectId,
    ]);

    console.log(`upload: uploading Sparkle latest copy → gs://${bucket}/${sparkleLatestObjectPath}`);
    run("gcloud", [
      "storage",
      "cp",
      sparkleZipPath,
      `gs://${bucket}/${sparkleLatestObjectPath}`,
      "--project",
      projectId,
    ]);
    sparkleSizeBytes = fs.statSync(sparkleZipPath).size;
  }

  if (fs.existsSync(appcastPath)) {
    console.log(`upload: uploading appcast → gs://${bucket}/${appcastObjectPath}`);
    run("gcloud", [
      "storage",
      "cp",
      appcastPath,
      `gs://${bucket}/${appcastObjectPath}`,
      "--project",
      projectId,
    ]);
  }

  const sizeBytes = fs.statSync(dmgPath).size;
  const registration = await registerPluginVersion({
    release,
    bucket,
    objectPath,
    latestObjectPath,
    releaseNotesObjectPath,
    sizeBytes,
    sparkleObjectPath: fs.existsSync(sparkleZipPath) ? sparkleObjectPath : null,
    sparkleLatestObjectPath: fs.existsSync(sparkleZipPath) ? sparkleLatestObjectPath : null,
    sparkleSizeBytes,
    sparkleDownloadUrl: fs.existsSync(sparkleZipPath)
      ? publicSparkleDownloadUrl({ version })
      : null,
    appcastObjectPath: fs.existsSync(appcastPath) ? appcastObjectPath : null,
    publishedBy: process.env.GCP_USER_EMAIL || null,
  });

  const registryApiUrl =
    process.env.NEXT_PUBLIC_REGISTRY_API_URL?.trim() ||
    "https://diskwise-registry.suherman.net";

  console.log("upload: done");
  console.log(`upload: gs://${bucket}/${objectPath}`);
  console.log(`upload: gs://${bucket}/${latestObjectPath}`);
  console.log(`upload: gs://${bucket}/${releaseNotesObjectPath}`);
  console.log(
    `upload: firestore ${registration.collection}/${registration.docId} (${registration.projectId})`
  );
  console.log(`upload: API ${registryApiUrl}/api/v1/plugins/${appId}/versions/latest`);

  return registration;
}

async function main() {
  await uploadRelease();
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { uploadRelease, dmgFileName, resolveAppId };
