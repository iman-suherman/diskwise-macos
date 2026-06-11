/**
 * Sync package.json version into Xcode project settings and Info.plist.
 */
const fs = require("fs");
const path = require("path");
const { assertSemver, versionSortKey } = require("./semver.cjs");

const root = path.join(__dirname, "..");

function syncAppVersion(version) {
  const parsed = assertSemver(version, "version");
  const buildNumber = String(versionSortKey(parsed));

  const projectYmlPath = path.join(root, "app/project.yml");
  let projectYml = fs.readFileSync(projectYmlPath, "utf8");
  projectYml = projectYml.replace(
    /MARKETING_VERSION:\s*[^\n]+/g,
    `MARKETING_VERSION: ${version}`
  );
  projectYml = projectYml.replace(
    /CURRENT_PROJECT_VERSION:\s*[^\n]+/g,
    `CURRENT_PROJECT_VERSION: ${buildNumber}`
  );
  fs.writeFileSync(projectYmlPath, projectYml, "utf8");

  const infoPlistPath = path.join(root, "app/DiskWise/Info.plist");
  let infoPlist = fs.readFileSync(infoPlistPath, "utf8");
  infoPlist = infoPlist.replace(
    /(<key>CFBundleShortVersionString<\/key>\s*<string>)[^<]+(<\/string>)/,
    `$1${version}$2`
  );
  infoPlist = infoPlist.replace(
    /(<key>CFBundleVersion<\/key>\s*<string>)[^<]+(<\/string>)/,
    `$1${buildNumber}$2`
  );
  fs.writeFileSync(infoPlistPath, infoPlist, "utf8");

  const sparkleKeyPath = path.join(root, "config/sparkle-public-ed-key.txt");
  if (fs.existsSync(sparkleKeyPath)) {
    const publicKey = fs.readFileSync(sparkleKeyPath, "utf8").trim();
    let projectYmlForKey = fs.readFileSync(projectYmlPath, "utf8");
    projectYmlForKey = projectYmlForKey.replace(
      /SPARKLE_PUBLIC_ED_KEY:\s*[^\n]+/,
      `SPARKLE_PUBLIC_ED_KEY: ${publicKey}`
    );
    fs.writeFileSync(projectYmlPath, projectYmlForKey, "utf8");
  }

  const pbxprojPath = path.join(root, "app/DiskWise.xcodeproj/project.pbxproj");
  if (fs.existsSync(pbxprojPath)) {
    let pbxproj = fs.readFileSync(pbxprojPath, "utf8");
    pbxproj = pbxproj.replace(/MARKETING_VERSION = [^;]+;/g, `MARKETING_VERSION = ${version};`);
    pbxproj = pbxproj.replace(
      /CURRENT_PROJECT_VERSION = [^;]+;/g,
      `CURRENT_PROJECT_VERSION = ${buildNumber};`
    );
    fs.writeFileSync(pbxprojPath, pbxproj, "utf8");
  }

  console.log(`sync-version: app version → ${version} (build ${buildNumber})`);
}

if (require.main === module) {
  const version = process.argv[2];
  if (!version) {
    console.error("Usage: node scripts/sync-app-version.cjs <version>");
    process.exit(1);
  }
  syncAppVersion(version);
}

module.exports = { syncAppVersion };
