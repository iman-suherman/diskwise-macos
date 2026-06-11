const { Storage } = require("@google-cloud/storage");

const storage = new Storage();

function parseGsUrl(url) {
  if (!url || !url.startsWith("gs://")) return null;
  const withoutScheme = url.slice("gs://".length);
  const slash = withoutScheme.indexOf("/");
  if (slash < 0) {
    return { bucket: withoutScheme, objectPath: "" };
  }
  return {
    bucket: withoutScheme.slice(0, slash),
    objectPath: withoutScheme.slice(slash + 1),
  };
}

function defaultAppcastObjectPath() {
  const prefix = (process.env.GCS_APP_PREFIX?.trim() || "releases").replace(/^\/+|\/+$/g, "");
  return `${prefix}/appcast.xml`;
}

function defaultBucket() {
  return process.env.GCS_APP_BUCKET?.trim() || null;
}

async function downloadObject(bucket, objectPath) {
  const [contents] = await storage.bucket(bucket).file(objectPath).download();
  return contents;
}

module.exports = {
  parseGsUrl,
  defaultAppcastObjectPath,
  defaultBucket,
  downloadObject,
};
