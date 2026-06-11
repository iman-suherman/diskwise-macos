const { getPluginCatalog, getLatestPluginVersion } = require("./firestore");
const {
  parseGsUrl,
  defaultAppcastObjectPath,
  defaultBucket,
  downloadObject,
} = require("./gcs");

async function resolveAppcastLocation(pluginId) {
  const catalog = await getPluginCatalog(pluginId);
  if (catalog?.appcastBucket && catalog?.appcastObjectPath) {
    return {
      bucket: catalog.appcastBucket,
      objectPath: catalog.appcastObjectPath,
    };
  }

  if (catalog?.appcastObjectPath) {
    const bucket = defaultBucket();
    if (bucket) {
      return { bucket, objectPath: catalog.appcastObjectPath };
    }
  }

  const latest = await getLatestPluginVersion(pluginId);
  const fromLatest = parseGsUrl(latest?.appcastUrl);
  if (fromLatest?.bucket && fromLatest.objectPath) {
    return fromLatest;
  }

  const bucket = defaultBucket();
  if (bucket) {
    return { bucket, objectPath: defaultAppcastObjectPath() };
  }

  return null;
}

async function fetchAppcastXml(pluginId) {
  const location = await resolveAppcastLocation(pluginId);
  if (!location) {
    const err = new Error("Appcast location is not configured");
    err.status = 404;
    throw err;
  }

  try {
    return await downloadObject(location.bucket, location.objectPath);
  } catch (err) {
    if (err?.code === 404) {
      const notFound = new Error(`Appcast not found at gs://${location.bucket}/${location.objectPath}`);
      notFound.status = 404;
      throw notFound;
    }
    throw err;
  }
}

module.exports = {
  resolveAppcastLocation,
  fetchAppcastXml,
};
