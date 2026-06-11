/**
 * Read app release state from Firestore (used by release + upload scripts).
 */
const { Firestore, FieldValue } = require("@google-cloud/firestore");
const path = require("path");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const { getCollectionName, getCatalogCollection } = require("./register-version.cjs");

const root = path.join(__dirname, "..");

function getFirestore() {
  applyGcpEnv(root);
  const projectId = resolveGcpProjectId(root);
  if (!projectId) {
    throw new Error("GCP_PROJECT_ID is not set. Run: npm run login");
  }
  return { firestore: new Firestore({ projectId }), projectId };
}

async function getLatestPluginRelease(pluginId) {
  try {
    const { firestore } = getFirestore();
    const catalogRef = firestore.collection(getCatalogCollection()).doc(pluginId);
    const catalogSnap = await catalogRef.get();
    const catalog = catalogSnap.exists ? catalogSnap.data() : null;

    const versionsSnap = await firestore
      .collection(getCollectionName())
      .where("pluginId", "==", pluginId)
      .orderBy("versionSortKey", "desc")
      .limit(1)
      .get();

    const latestVersion = versionsSnap.empty ? null : versionsSnap.docs[0].data();
    const lastReleasedCommit =
      catalog?.lastReleasedCommit || latestVersion?.gitCommit || null;

    return {
      catalog,
      latestVersion,
      lastReleasedCommit,
      lastReleasedVersion: catalog?.lastReleasedVersion || latestVersion?.version || null,
      source: "firestore",
    };
  } catch (err) {
    if (err.code === 5 || /NOT_FOUND/i.test(String(err.message))) {
      return {
        catalog: null,
        latestVersion: null,
        lastReleasedCommit: null,
        lastReleasedVersion: null,
        source: "firestore-unavailable",
      };
    }
    if (/index/i.test(String(err.message))) {
      const { firestore } = getFirestore();
      const snapshot = await firestore.collection(getCollectionName()).get();
      const versions = snapshot.docs
        .map((doc) => doc.data())
        .filter((row) => row.pluginId === pluginId)
        .sort((a, b) => (b.versionSortKey || 0) - (a.versionSortKey || 0));
      const latestVersion = versions[0] || null;
      return {
        catalog: null,
        latestVersion,
        lastReleasedCommit: latestVersion?.gitCommit || null,
        lastReleasedVersion: latestVersion?.version || null,
        source: "firestore-fallback",
      };
    }
    throw err;
  }
}

async function markReleaseCheckpoint(pluginId, gitCommit, version) {
  const { firestore } = getFirestore();
  await firestore
    .collection(getCatalogCollection())
    .doc(pluginId)
    .set(
      {
        pluginId,
        lastReleasedCommit: gitCommit,
        lastReleasedVersion: version,
        lastReleaseCheckedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
}

module.exports = {
  getLatestPluginRelease,
  markReleaseCheckpoint,
};
