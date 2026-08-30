/**
 * Decide whether repo changes require a website, registry, or app release deploy.
 */
const { getChangedFiles } = require("./generate-release-notes.cjs");

const WEBSITE_DEPLOY_PREFIXES = ["website/", "releases/sparkle/", "release-notes/"];

const REGISTRY_DEPLOY_PREFIXES = [
  "services/registry-api/",
  "firestore/",
  "scripts/deploy-registry-api.cjs",
  "scripts/build-registry-image.sh",
];

const APP_RELEASE_PREFIXES = [
  "Sources/",
  "Tests/",
  "Package.swift",
  "scripts/release.sh",
  "scripts/release-publish.cjs",
  "scripts/sign-and-notarize.sh",
];

const APP_RELEASE_PATH_PATTERNS = [/^app\/DiskWise\/.*\.swift$/];

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
];

function requiresWebsiteDeploy(changedFiles) {
  if (!changedFiles.length) return false;
  return changedFiles.some((file) =>
    WEBSITE_DEPLOY_PREFIXES.some((prefix) => file.startsWith(prefix)),
  );
}

function requiresRegistryDeploy(changedFiles) {
  if (!changedFiles.length) return false;
  return changedFiles.some((file) =>
    REGISTRY_DEPLOY_PREFIXES.some((prefix) =>
      prefix.endsWith(".cjs") || prefix.endsWith(".sh")
        ? file === prefix
        : file.startsWith(prefix),
    ),
  );
}

/**
 * True when changes need a new notarized DMG (product code), not version/checkpoint bookkeeping.
 */
function requiresAppRelease(changedFiles) {
  if (!changedFiles.length) return false;
  if (isDeployCheckpointOnlyChange(changedFiles)) return false;
  return changedFiles.some(
    (file) =>
      APP_RELEASE_PREFIXES.some((prefix) =>
        prefix.includes(".") && !prefix.endsWith("/")
          ? file === prefix
          : file.startsWith(prefix),
      ) || APP_RELEASE_PATH_PATTERNS.some((pattern) => pattern.test(file)),
  );
}

function requiresDeployForRepo(repo, changedFiles) {
  switch (repo) {
    case "diskwise-website":
      return requiresWebsiteDeploy(changedFiles);
    case "diskwise-registry":
      return requiresRegistryDeploy(changedFiles);
    case "diskwise-app":
      return requiresAppRelease(changedFiles);
    default:
      return changedFiles.length > 0;
  }
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
  requiresRegistryDeploy,
  requiresAppRelease,
  requiresDeployForRepo,
  isDeployCheckpointOnlyChange,
  changedFilesSince,
};
