const { Firestore } = require("@google-cloud/firestore");
const { normalizeChannel, pickLatestForChannel } = require("./channels");

const projectId = process.env.GCP_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT;
const collectionName =
  process.env.FIRESTORE_APP_COLLECTION?.trim() || "app_versions";
const catalogCollection =
  process.env.FIRESTORE_APP_CATALOG?.trim() || "app_catalog";

const firestore = new Firestore({ projectId });

function isFirestoreNotReady(err) {
  return err?.code === 5 || /NOT_FOUND/i.test(String(err.message));
}

function stripInternalFields(data) {
  if (!data) return data;
  const { versionSortKey, ...rest } = data;
  return rest;
}

function sortVersions(versions) {
  return versions.sort((a, b) => (b.versionSortKey || 0) - (a.versionSortKey || 0));
}

async function listAllVersions(pluginId) {
  try {
    const snapshot = await firestore.collection(collectionName).get();
    return sortVersions(
      snapshot.docs
        .map((doc) => doc.data())
        .filter((row) => row.pluginId === pluginId)
        .map(stripInternalFields)
    );
  } catch (err) {
    if (isFirestoreNotReady(err)) return [];
    throw err;
  }
}

async function listPlugins() {
  try {
    const snapshot = await firestore.collection(catalogCollection).get();
    return snapshot.docs
      .map((doc) => doc.data())
      .sort((a, b) => (a.pluginId || "").localeCompare(b.pluginId || ""));
  } catch (err) {
    if (isFirestoreNotReady(err)) return [];
    throw err;
  }
}

async function listPluginVersions(pluginId) {
  try {
    const snapshot = await firestore
      .collection(collectionName)
      .where("pluginId", "==", pluginId)
      .orderBy("versionSortKey", "desc")
      .get();
    return snapshot.docs.map((doc) => stripInternalFields(doc.data()));
  } catch (err) {
    if (/index/i.test(String(err.message))) {
      return listAllVersions(pluginId);
    }
    if (isFirestoreNotReady(err)) return [];
    throw err;
  }
}

async function getPluginVersion(pluginId, version) {
  try {
    const docId = `${pluginId}__${version}`;
    const doc = await firestore.collection(collectionName).doc(docId).get();
    if (!doc.exists) return null;
    return stripInternalFields(doc.data());
  } catch (err) {
    if (isFirestoreNotReady(err)) return null;
    throw err;
  }
}

async function getPluginCatalog(pluginId) {
  try {
    const doc = await firestore.collection(catalogCollection).doc(pluginId).get();
    if (!doc.exists) return null;
    return doc.data();
  } catch (err) {
    if (isFirestoreNotReady(err)) return null;
    throw err;
  }
}

async function getLatestPluginVersion(pluginId, options = {}) {
  const channel = normalizeChannel(options.channel);
  try {
    const snapshot = await firestore
      .collection(collectionName)
      .where("pluginId", "==", pluginId)
      .orderBy("versionSortKey", "desc")
      .limit(channel === "stable" ? 20 : 1)
      .get();
    if (snapshot.empty) return null;
    const versions = snapshot.docs.map((doc) => stripInternalFields(doc.data()));
    return pickLatestForChannel(versions, channel);
  } catch (err) {
    if (/index/i.test(String(err.message))) {
      const versions = await listAllVersions(pluginId);
      return pickLatestForChannel(versions, channel);
    }
    if (isFirestoreNotReady(err)) return null;
    throw err;
  }
}

module.exports = {
  collectionName,
  catalogCollection,
  listPlugins,
  listPluginVersions,
  getPluginVersion,
  getPluginCatalog,
  getLatestPluginVersion,
};
