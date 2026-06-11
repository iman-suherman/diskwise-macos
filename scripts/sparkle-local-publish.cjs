/**
 * Publish Sparkle update artifacts for local testing via npm run dev:website.
 * Writes ZIP + appcast.xml into website/public/ (served at http://127.0.0.1:3000).
 */
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const { loadDotenv } = require("./load-dotenv.cjs");
const { generateReleaseNotes, writeReleaseArtifacts } = require("./generate-release-notes.cjs");
const { generateAppcast } = require("./generate-appcast.cjs");
const {
  resolveLocalDownloadBase,
  resolveLocalAppcastUrl,
  sparkleZipFileName,
} = require("./public-download-url.cjs");

const root = path.join(__dirname, "..");
const shell = process.platform === "win32";

function run(command, args) {
  const r = spawnSync(command, args, {
    stdio: "inherit",
    cwd: root,
    shell,
    env: { ...process.env, SPARKLE_LOCAL: "1", LOCAL_RELEASE: "1" },
  });
  if (r.error) throw r.error;
  if (r.status !== 0) process.exit(r.status ?? 1);
}

function readPackageVersion() {
  const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
  return pkg.version;
}

function resolveAppPath() {
  const candidates = [
    process.env.DISKWISE_APP_PATH,
    path.join(root, ".build/DerivedData/Build/Products/Release/DiskWise.app"),
    path.join(root, ".build/DerivedDataSparkle/Build/Products/Release/DiskWise.app"),
    path.join(root, ".build/DerivedData/Build/Products/Debug/DiskWise.app"),
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }

  console.error("sparkle:local: DiskWise.app not found. Build first:");
  console.error("  npm run release:local   (signed release)");
  console.error("  npm run build:app       (debug)");
  process.exit(1);
}

function main() {
  loadDotenv(root);

  const version = process.env.SPARKLE_LOCAL_VERSION?.trim() || readPackageVersion();
  const appPath = resolveAppPath();
  const downloadBase = resolveLocalDownloadBase();
  const appcastUrl = resolveLocalAppcastUrl();
  const websiteDownloads = path.join(root, "website", "public", "downloads");
  const sparkleArchives = path.join(root, "releases", "sparkle");
  const zipName = sparkleZipFileName(version);
  const websiteZipPath = path.join(websiteDownloads, zipName);
  const sparkleZipPath = path.join(sparkleArchives, zipName);

  fs.mkdirSync(websiteDownloads, { recursive: true });
  fs.mkdirSync(sparkleArchives, { recursive: true });

  console.log("sparkle:local: packaging update for local website");
  console.log(`  app:     ${appPath}`);
  console.log(`  version: ${version}`);
  console.log(`  feed:    ${appcastUrl}`);
  console.log(`  zip URL: ${downloadBase}/${zipName}`);

  run("bash", ["scripts/package-zip.sh", appPath, version, sparkleZipPath]);
  fs.copyFileSync(sparkleZipPath, websiteZipPath);
  console.log(`sparkle:local: copied zip → ${websiteZipPath}`);

  const dmgCandidates = [
    process.env.OUTPUT_DMG?.trim(),
    path.join(root, "releases", `diskwise-macos-${version}.dmg`),
  ].filter(Boolean);
  for (const dmgPath of dmgCandidates) {
    if (!fs.existsSync(dmgPath)) continue;
    const dmgName = path.basename(dmgPath);
    const websiteDmgPath = path.join(websiteDownloads, dmgName);
    fs.copyFileSync(dmgPath, websiteDmgPath);
    console.log(`sparkle:local: copied dmg → ${websiteDmgPath}`);
    break;
  }

  const release = generateReleaseNotes({ version });
  writeReleaseArtifacts(release);

  generateAppcast({
    release,
    downloadBase,
    archivesDir: sparkleArchives,
  });

  console.log("");
  console.log("sparkle:local: done");
  console.log("  1. npm run dev:website");
  console.log(`  2. Open ${appcastUrl} to verify the feed`);
  console.log("  3. Launch a build with an older version to test the update prompt");
}

main();
