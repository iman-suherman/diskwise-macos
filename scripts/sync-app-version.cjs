/**
 * Sync package.json version into Xcode project settings and Info.plist.
 */
const fs = require("fs");
const path = require("path");
const { assertSemver, versionSortKey } = require("./semver.cjs");

const root = path.join(__dirname, "..");

function replaceMacOsYamlVersions(projectYml, version, buildNumber) {
  const macId = "PRODUCT_BUNDLE_IDENTIFIER: net.suherman.diskwise\n";
  const iosId = "PRODUCT_BUNDLE_IDENTIFIER: net.suherman.diskwise.ios";
  const start = projectYml.indexOf(macId);
  if (start < 0) {
    throw new Error("sync-version: DiskWise macOS target not found in project.yml");
  }
  const iosStart = projectYml.indexOf(iosId);
  const end = iosStart > start ? iosStart : projectYml.length;
  const head = projectYml.slice(0, start);
  let block = projectYml.slice(start, end);
  const tail = projectYml.slice(end);
  if (!/CURRENT_PROJECT_VERSION:/.test(block) || !/MARKETING_VERSION:/.test(block)) {
    throw new Error("sync-version: macOS MARKETING_VERSION / CURRENT_PROJECT_VERSION not found");
  }
  block = block.replace(
    /CURRENT_PROJECT_VERSION:\s*[^\n]+/,
    `CURRENT_PROJECT_VERSION: ${buildNumber}`
  );
  block = block.replace(/MARKETING_VERSION:\s*[^\n]+/, `MARKETING_VERSION: ${version}`);
  return head + block + tail;
}

function replaceMatchingPbxprojVersions(pbxproj, previousVersion, previousBuild, version, buildNumber) {
  if (previousVersion && previousVersion !== version) {
    pbxproj = pbxproj.split(`MARKETING_VERSION = ${previousVersion};`).join(
      `MARKETING_VERSION = ${version};`
    );
  }
  if (previousBuild && previousBuild !== buildNumber) {
    pbxproj = pbxproj.split(`CURRENT_PROJECT_VERSION = ${previousBuild};`).join(
      `CURRENT_PROJECT_VERSION = ${buildNumber};`
    );
  }
  return pbxproj;
}

function syncAppVersion(version) {
  const parsed = assertSemver(version, "version");
  const buildNumber = String(versionSortKey(parsed));

  const projectYmlPath = path.join(root, "app/project.yml");
  const projectYml = replaceMacOsYamlVersions(
    fs.readFileSync(projectYmlPath, "utf8"),
    version,
    buildNumber
  );
  fs.writeFileSync(projectYmlPath, projectYml, "utf8");

  const infoPlistPath = path.join(root, "app/DiskWise/Info.plist");
  let infoPlist = fs.readFileSync(infoPlistPath, "utf8");
  const previousVersion =
    infoPlist.match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/)?.[1] ||
    "";
  const previousBuild =
    infoPlist.match(/<key>CFBundleVersion<\/key>\s*<string>([^<]+)<\/string>/)?.[1] || "";
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
    const pbxproj = replaceMatchingPbxprojVersions(
      fs.readFileSync(pbxprojPath, "utf8"),
      previousVersion,
      previousBuild,
      version,
      buildNumber
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
