/**
 * Regenerate and publish release notes for an existing version (no rebuild).
 *
 * Usage: node scripts/republish-notes.cjs [version]
 */
const path = require("path");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const { assertSemver } = require("./semver.cjs");
const { generateReleaseNotes, writeReleaseArtifacts } = require("./generate-release-notes.cjs");
const { registerPluginVersion } = require("./register-version.cjs");
const { resolveDownloadBase } = require("./public-download-url.cjs");
const { dmgFileName, resolveAppId, uploadSparkleDeltas } = require("./upload-release.cjs");
const { generateAppcast } = require("./generate-appcast.cjs");

const root = path.join(__dirname, "..");

async function republishNotes(version) {
  applyGcpEnv(root);
  const projectId = resolveGcpProjectId(root);
  if (!projectId) {
    throw new Error("GCP_PROJECT_ID is not set. Run: npm run login");
  }

  assertSemver(version, "version");
  const packageJson = require(path.join(root, "package.json"));
  const appId = resolveAppId(packageJson);
  const release = generateReleaseNotes({ version, pluginId: appId });
  const artifacts = writeReleaseArtifacts(release);

  console.log(`republish-notes: ${release.summary}`);
  console.log(`republish-notes: wrote ${artifacts.jsonPath}`);

  const prefix = (process.env.GCS_APP_PREFIX?.trim() || "releases").replace(/^\/+|\/+$/g, "");
  const bucket = process.env.GCS_APP_BUCKET?.trim() || `${projectId}-diskwise`;
  const releaseNotesObjectPath = `${prefix}/${version}/release-${version}.json`;
  const releaseNotesMarkdownPath = `${prefix}/${version}/release-${version}.md`;
  const appcastObjectPath = `${prefix}/appcast.xml`;

  const { spawnSync } = require("child_process");
  const shell = process.platform === "win32";
  function run(command, args) {
    const r = spawnSync(command, args, {
      stdio: "inherit",
      cwd: root,
      shell,
      env: process.env,
    });
    if (r.status !== 0) process.exit(r.status ?? 1);
  }

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

  const sparkleZipPath = path.join(root, "releases", "sparkle", `DiskWise-${version}.zip`);
  const sparkleArchivesDir = path.join(root, "releases", "sparkle");
  if (require("fs").existsSync(sparkleZipPath)) {
    const appcastArtifacts = generateAppcast({
      release,
      downloadBase: resolveDownloadBase({ ...process.env, SPARKLE_LOCAL: "0", LOCAL_RELEASE: "0" }),
      copyToWebsite: false,
    });
    run("gcloud", [
      "storage",
      "cp",
      appcastArtifacts.appcastPath,
      `gs://${bucket}/${appcastObjectPath}`,
      "--project",
      projectId,
    ]);
    uploadSparkleDeltas({
      bucket,
      prefix,
      projectId,
      version,
      archivesDir: sparkleArchivesDir,
    });
  }

  const dmgPath = path.join(root, "releases", dmgFileName(appId, version));
  const objectPath = `${prefix}/${version}/${dmgFileName(appId, version)}`;
  const latestObjectPath = `${prefix}/latest/${dmgFileName(appId, version)}`;

  await registerPluginVersion({
    release,
    bucket,
    objectPath,
    latestObjectPath,
    releaseNotesObjectPath,
    sizeBytes: require("fs").existsSync(dmgPath) ? require("fs").statSync(dmgPath).size : null,
    sparkleObjectPath: require("fs").existsSync(sparkleZipPath)
      ? `${prefix}/${version}/DiskWise-${version}.zip`
      : null,
    sparkleLatestObjectPath: require("fs").existsSync(sparkleZipPath)
      ? `${prefix}/latest/DiskWise-${version}.zip`
      : null,
    appcastObjectPath: require("fs").existsSync(sparkleZipPath) ? appcastObjectPath : null,
    publishedBy: process.env.GCP_USER_EMAIL || null,
  });

  console.log(`republish-notes: updated Firestore app_versions/${appId}__${version}`);
}

if (require.main === module) {
  const packageJson = require(path.join(root, "package.json"));
  const version = process.argv[2] || packageJson.version;
  republishNotes(version).catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { republishNotes };
