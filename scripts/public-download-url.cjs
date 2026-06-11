/**
 * Build public DMG download URLs via the Cloudflare GCS proxy (private bucket).
 */
const path = require("path");

const DEFAULT_DOWNLOAD_BASE = "https://diskwise-download.suherman.net/downloads";

function resolveDownloadBase(env = process.env) {
  return (
    env.PUBLIC_DOWNLOAD_BASE_URL?.trim() ||
    env.NEXT_PUBLIC_DOWNLOAD_BASE_URL?.trim() ||
    DEFAULT_DOWNLOAD_BASE
  ).replace(/\/$/, "");
}

function dmgFileName(objectPath, version, appId) {
  if (objectPath) return path.basename(objectPath);
  if (version && appId) return `${appId}-${version}.dmg`;
  return "latest.dmg";
}

function publicDownloadUrl({ base, objectPath, version, appId }) {
  const root = (base || resolveDownloadBase()).replace(/\/$/, "");
  return `${root}/${dmgFileName(objectPath, version, appId)}`;
}

function publicLatestDownloadUrl({ base, latestObjectPath }) {
  const root = (base || resolveDownloadBase()).replace(/\/$/, "");
  const fileName = latestObjectPath ? path.basename(latestObjectPath) : "latest.dmg";
  return `${root}/${fileName}`;
}

module.exports = {
  DEFAULT_DOWNLOAD_BASE,
  resolveDownloadBase,
  dmgFileName,
  publicDownloadUrl,
  publicLatestDownloadUrl,
};
