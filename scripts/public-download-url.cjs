/**
 * Build public DMG download URLs via the Cloudflare GCS proxy (private bucket).
 */
const path = require("path");

const DEFAULT_DOWNLOAD_BASE = "https://diskwise-download.suherman.net/downloads";
const DEFAULT_LOCAL_DOWNLOAD_BASE = "http://127.0.0.1:3000/downloads";
const DEFAULT_LOCAL_WEBSITE_BASE = "http://127.0.0.1:3000";

function resolveDownloadBase(env = process.env) {
  if (env.SPARKLE_LOCAL === "1" || env.LOCAL_RELEASE === "1") {
    return resolveLocalDownloadBase(env);
  }
  return (
    env.PUBLIC_DOWNLOAD_BASE_URL?.trim() ||
    env.NEXT_PUBLIC_DOWNLOAD_BASE_URL?.trim() ||
    DEFAULT_DOWNLOAD_BASE
  ).replace(/\/$/, "");
}

function resolveLocalDownloadBase(env = process.env) {
  return (
    env.LOCAL_DOWNLOAD_BASE_URL?.trim() ||
    env.NEXT_PUBLIC_LOCAL_DOWNLOAD_BASE_URL?.trim() ||
    DEFAULT_LOCAL_DOWNLOAD_BASE
  ).replace(/\/$/, "");
}

function resolveLocalWebsiteBase(env = process.env) {
  return (
    env.LOCAL_WEBSITE_URL?.trim() ||
    env.NEXT_PUBLIC_LOCAL_WEBSITE_URL?.trim() ||
    DEFAULT_LOCAL_WEBSITE_BASE
  ).replace(/\/$/, "");
}

function resolveLocalAppcastUrl(env = process.env) {
  const configured = env.LOCAL_APPCAST_URL?.trim() || env.SPARKLE_APPCAST_URL_LOCAL?.trim();
  if (configured) return configured;
  return `${resolveLocalWebsiteBase(env)}/appcast.xml`;
}

function dmgFileName(objectPath, version, appId) {
  if (objectPath) return path.basename(objectPath);
  if (version && appId) return `${appId}-${version}.dmg`;
  return "latest.dmg";
}

function sparkleZipFileName(version) {
  return `DiskWise-${version}.zip`;
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

function publicSparkleDownloadUrl({ base, version }) {
  const root = (base || resolveDownloadBase()).replace(/\/$/, "");
  return `${root}/${sparkleZipFileName(version)}`;
}

module.exports = {
  DEFAULT_DOWNLOAD_BASE,
  DEFAULT_LOCAL_DOWNLOAD_BASE,
  DEFAULT_LOCAL_WEBSITE_BASE,
  resolveDownloadBase,
  resolveLocalDownloadBase,
  resolveLocalWebsiteBase,
  resolveLocalAppcastUrl,
  dmgFileName,
  sparkleZipFileName,
  publicDownloadUrl,
  publicLatestDownloadUrl,
  publicSparkleDownloadUrl,
};
