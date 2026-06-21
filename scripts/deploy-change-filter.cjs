/**
 * Decide whether repo changes require a website or app release deploy.
 */
const { getChangedFiles } = require("./generate-release-notes.cjs");

const WEBSITE_DEPLOY_PREFIXES = ["website/", "releases/sparkle/", "release-notes/"];

const DEPLOY_CHECKPOINT_PREFIXES = ["scripts/", "release-notes/", "logs/"];

const DEPLOY_CHECKPOINT_EXACT = new Set([
  "package.json",
  "app/project.yml",
  "app/DiskWise/Info.plist",
]);

const DEPLOY_CHECKPOINT_PATH_PATTERNS = [
  /^app\/DiskWise\.xcodeproj\//,
  /^app\/DiskWise\/Assets\.xcassets\//,
  /^app\/DiskWise\//,
  /^app\/DiskWise\.xcodeproj\//,
];

function requiresWebsiteDeploy(changedFiles) {
  if (!changedFiles.length) return false;
  return changedFiles.some((file) =>
    WEBSITE_DEPLOY_PREFIXES.some((prefix) => file.startsWith(prefix)),
  );
}

function isDeployCheckpointOnlyChange(changedFiles) {
  if (!changedFiles.length) return true;
  return changedFiles.every((file) => {
    if (DEPLOY_CHECKPOINT_PREFIXES.some((prefix) => file.startsWith(prefix))) return true;
    if (DEPLOY_CHECKPOINT_EXACT.has(file)) return true;
    if (DEPLOY_CHECKPOINT_PATH_PATTERNS.some((pattern) => pattern.test(file))) return true;
    return false;
  });
}

function changedFilesSince(baseSha, headSha) {
  if (!baseSha || !headSha) return [];
  if (baseSha === headSha) return [];
  return getChangedFiles(`${baseSha}..${headSha}`);
}

module.exports = {
  requiresWebsiteDeploy,
  isDeployCheckpointOnlyChange,
  changedFilesSince,
};
