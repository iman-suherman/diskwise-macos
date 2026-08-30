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
  "Sources/DiskScannerKit/",
  "Sources/DatabaseKit/",
  "Sources/MetadataKit/",
  "Sources/DuplicateKit/",
  "Sources/CleanupKit/",
  "Sources/AIKit/",
  "Sources/MaintenanceKit/",
  "Tests/DiskScannerKitTests/",
  "Tests/DatabaseKitTests/",
  "Tests/DuplicateKitTests/",
  "Tests/AIKitTests/",
  "Tests/MaintenanceKitTests/",
  "scripts/release.sh",
  "scripts/release-publish.cjs",
  "scripts/sign-and-notarize.sh",
];

const APP_RELEASE_PATH_PATTERNS = [/^app\/DiskWise\/.*\.swift$/];

const APP_RELEASE_EXCLUDE_PREFIXES = [
  "Sources/PhotosKit/",
  "Tests/PhotosKitTests/",
  "app/DiskWiseiOS/",
];

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
 * True when changes need a new notarized DMG (macOS product code), not iOS/PhotosKit.
 */
function requiresAppRelease(changedFiles) {
  if (!changedFiles.length) return false;
  if (isDeployCheckpointOnlyChange(changedFiles)) return false;
  const macOSFiles = changedFiles.filter(
    (file) =>
      !APP_RELEASE_EXCLUDE_PREFIXES.some((prefix) => file.startsWith(prefix)),
  );
  if (!macOSFiles.length) return false;
  return macOSFiles.some(
    (file) =>
      APP_RELEASE_PREFIXES.some((prefix) =>
        prefix.includes(".") && !prefix.endsWith("/")
          ? file === prefix
          : file.startsWith(prefix),
      ) || APP_RELEASE_PATH_PATTERNS.some((pattern) => pattern.test(file)),
  );
}

const IOS_RELEASE_PREFIXES = [
  "Sources/PhotosKit/",
  "Tests/PhotosKitTests/",
  "app/DiskWiseiOS/",
  "app-store-connect/",
  "scripts/build-ios.sh",
  "scripts/publish-testflight.sh",
  "scripts/ensure-asc-app.sh",
  "scripts/upload-app-store-listing.py",
  "scripts/submit-app-store-review.py",
  "scripts/set-app-store-price-free.py",
  "scripts/prepare-app-store-metadata.py",
  "scripts/capture-app-store-screenshots.sh",
  "docs/ios-photos.md",
];

function requiresIosRelease(changedFiles) {
  if (!changedFiles.length) return false;
  return changedFiles.some((file) =>
    IOS_RELEASE_PREFIXES.some((prefix) =>
      prefix.endsWith(".sh") || prefix.endsWith(".py") || prefix.endsWith(".md")
        ? file === prefix
        : file.startsWith(prefix),
    ),
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
    case "diskwise-ios":
      return requiresIosRelease(changedFiles);
    case "diskwise-download":
      return false;
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
  requiresIosRelease,
  requiresDeployForRepo,
  isDeployCheckpointOnlyChange,
  changedFilesSince,
};
