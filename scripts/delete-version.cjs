/**
 * Delete a registered app version from Firestore and refresh catalog latest pointer.
 *
 * Usage: node scripts/delete-version.cjs <pluginId> <version>
 */
const { Firestore } = require("@google-cloud/firestore");
const path = require("path");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const { versionDocId, versionSortKey, parseSemver } = require("./semver.cjs");
const { getCollectionName, getCatalogCollection } = require("./register-version.cjs");

const root = path.join(__dirname, "..");

async function listPluginVersions(firestore, pluginId) {
  const snapshot = await firestore.collection(getCollectionName()).get();
  return snapshot.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((row) => row.pluginId === pluginId)
    .sort((a, b) => (b.versionSortKey || 0) - (a.versionSortKey || 0));
}

async function deletePluginVersion(pluginId, version) {
  applyGcpEnv(root);
  const projectId = resolveGcpProjectId(root);
  if (!projectId) {
    throw new Error("GCP_PROJECT_ID is not set. Run: npm run login");
  }

  const parsed = parseSemver(version);
  if (!parsed) {
    throw new Error(`Invalid version: ${version}`);
  }

  const firestore = new Firestore({ projectId });
  const collection = getCollectionName();
  const docId = versionDocId(pluginId, version);
  const docRef = firestore.collection(collection).doc(docId);
  const existing = await docRef.get();

  if (!existing.exists) {
    console.log(`delete-version: ${collection}/${docId} not found — nothing to delete`);
  } else {
    await docRef.delete();
    console.log(`delete-version: deleted ${collection}/${docId}`);
  }

  const remaining = await listPluginVersions(firestore, pluginId);
  const latest = remaining[0] || null;
  const catalogRef = firestore.collection(getCatalogCollection()).doc(pluginId);

  if (latest) {
    await catalogRef.set(
      {
        pluginId,
        latestVersion: latest.version,
        latestVersionSortKey: latest.versionSortKey || versionSortKey(parseSemver(latest.version)),
        lastReleasedVersion: latest.version,
        lastReleasedCommit: latest.gitCommit || null,
        updatedAt: new Date(),
      },
      { merge: true }
    );
    console.log(`delete-version: catalog latest → v${latest.version}`);
  } else {
    await catalogRef.set(
      {
        latestVersion: null,
        latestVersionSortKey: null,
        lastReleasedVersion: null,
        updatedAt: new Date(),
      },
      { merge: true }
    );
    console.log("delete-version: catalog latest cleared (no versions remain)");
  }

  return { docId, remainingCount: remaining.length, latestVersion: latest?.version || null };
}

if (require.main === module) {
  const pluginId = process.argv[2];
  const version = process.argv[3];
  if (!pluginId || !version) {
    console.error("Usage: node scripts/delete-version.cjs <pluginId> <version>");
    process.exit(1);
  }

  deletePluginVersion(pluginId, version)
    .then((result) => {
      console.log(
        `delete-version: done — ${result.remainingCount} version(s) remain, latest v${result.latestVersion || "none"}`
      );
    })
    .catch((err) => {
      console.error(err);
      process.exit(1);
    });
}

module.exports = { deletePluginVersion };
