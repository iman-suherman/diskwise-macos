/**
 * Register an app version in Firestore after GCS upload.
 */
const { Firestore, FieldValue } = require("@google-cloud/firestore");
const path = require("path");
const fs = require("fs");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const { versionSortKey, versionDocId } = require("./semver.cjs");
const {
  publicDownloadUrl,
  publicLatestDownloadUrl,
  resolveDownloadBase,
  resolvePublicAppcastUrl,
} = require("./public-download-url.cjs");

const root = path.join(__dirname, "..");

function getCollectionName() {
  return process.env.FIRESTORE_APP_COLLECTION?.trim() || "app_versions";
}

function getCatalogCollection() {
  return process.env.FIRESTORE_APP_CATALOG?.trim() || "app_catalog";
}

async function registerPluginVersion({
  release,
  bucket,
  objectPath,
  latestObjectPath,
  releaseNotesObjectPath,
  sizeBytes,
  sparkleObjectPath,
  sparkleLatestObjectPath,
  sparkleSizeBytes,
  sparkleDownloadUrl,
  appcastObjectPath,
  publishedBy,
}) {
  applyGcpEnv(root);

  const projectId = resolveGcpProjectId(root);
  if (!projectId) {
    throw new Error("GCP_PROJECT_ID is not set. Run: npm run login");
  }

  const firestore = new Firestore({ projectId });
  const collection = getCollectionName();
  const docId = versionDocId(release.pluginId, release.version);
  const sortKey = versionSortKey(release.semver);
  const artifactFileName = path.basename(objectPath);

  const record = {
    pluginId: release.pluginId,
    displayName: release.displayName,
    publisher: release.publisher,
    version: release.version,
    semver: release.version,
    versionSortKey: sortKey,
    channel: release.channel || process.env.RELEASE_CHANNEL?.trim() || "stable",
    summary: release.summary,
    releaseNotes: release.releaseNotes,
    releaseNotesMarkdown: release.releaseNotesMarkdown,
    gcs: {
      bucket,
      objectPath,
      latestObjectPath,
      releaseNotesObjectPath,
      vsixFileName: artifactFileName,
    },
    downloadUrl: `gs://${bucket}/${objectPath}`,
    publicDownloadUrl: publicDownloadUrl({
      base: resolveDownloadBase(),
      objectPath,
      version: release.version,
      appId: release.pluginId,
    }),
    latestDownloadUrl: latestObjectPath ? `gs://${bucket}/${latestObjectPath}` : null,
    publicLatestDownloadUrl: latestObjectPath
      ? publicLatestDownloadUrl({
          base: resolveDownloadBase(),
          latestObjectPath,
        })
      : null,
    releaseNotesUrl: releaseNotesObjectPath
      ? `gs://${bucket}/${releaseNotesObjectPath}`
      : null,
    sizeBytes: sizeBytes || null,
    sparkle: sparkleObjectPath
      ? {
          objectPath: sparkleObjectPath,
          latestObjectPath: sparkleLatestObjectPath,
          sizeBytes: sparkleSizeBytes || null,
          publicDownloadUrl: sparkleDownloadUrl || null,
        }
      : null,
    appcastUrl: appcastObjectPath ? `gs://${bucket}/${appcastObjectPath}` : null,
    publicAppcastUrl: resolvePublicAppcastUrl(process.env, release.pluginId),
    gitCommit: release.gitCommit || null,
    gitTag: release.gitTag || null,
    previousTag: release.previousTag || null,
    commitCount: release.commitCount || 0,
    publishedBy: publishedBy || null,
    publishedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  await firestore.collection(collection).doc(docId).set(record, { merge: true });

  await firestore
    .collection(getCatalogCollection())
    .doc(release.pluginId)
    .set(
      {
        pluginId: release.pluginId,
        displayName: release.displayName,
        publisher: release.publisher,
        latestVersion: release.version,
        latestVersionSortKey: sortKey,
        lastReleasedCommit: release.gitCommit || null,
        lastReleasedVersion: release.version,
        appcastBucket: appcastObjectPath ? bucket : null,
        appcastObjectPath: appcastObjectPath || null,
        publicAppcastUrl: resolvePublicAppcastUrl(process.env, release.pluginId),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

  return { projectId, collection, docId, record };
}

if (require.main === module) {
  const releasePath = process.argv[2];
  if (!releasePath) {
    console.error("Usage: node scripts/register-version.cjs <release-json-path>");
    process.exit(1);
  }

  const release = JSON.parse(fs.readFileSync(releasePath, "utf8"));
  registerPluginVersion({
    release,
    bucket: process.env.GCS_APP_BUCKET,
    objectPath: process.env.REGISTER_OBJECT_PATH,
    latestObjectPath: process.env.REGISTER_LATEST_OBJECT_PATH,
    releaseNotesObjectPath: process.env.REGISTER_RELEASE_NOTES_OBJECT_PATH,
    sizeBytes: Number(process.env.REGISTER_SIZE_BYTES || 0) || null,
    publishedBy: process.env.GCP_USER_EMAIL || null,
  })
    .then((result) => {
      console.log(
        `register: wrote ${result.collection}/${result.docId} in project ${result.projectId}`
      );
    })
    .catch((err) => {
      console.error(err);
      process.exit(1);
    });
}

module.exports = { registerPluginVersion, getCollectionName, getCatalogCollection };
