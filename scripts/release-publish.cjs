/**
 * Full release pipeline: semver bump, build/sign/notarize, GCS upload, Firestore register.
 */
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const { loadDotenv } = require("./load-dotenv.cjs");
const { getLatestPluginRelease, markReleaseCheckpoint } = require("./registry-read.cjs");
const { bumpSemver, assertSemver } = require("./semver.cjs");
const { suggestBumpLevel, getCommits, isMetaCommit, getChangedFiles } = require("./generate-release-notes.cjs");
const { uploadRelease, dmgFileName, resolveAppId } = require("./upload-release.cjs");
const { syncAppVersion } = require("./sync-app-version.cjs");
const { getDeployTarget } = require("./deploy-config.cjs");
const { recordDirectDeployOutcome } = require("./deploy-record-direct.cjs");

const root = path.join(__dirname, "..");
const shell = process.platform === "win32";
const packageJsonPath = path.join(root, "package.json");
const DEPLOY_REPO = "diskwise-app";
const DEPLOY_NPM_SCRIPT = "release:direct";
const deployTarget = getDeployTarget(DEPLOY_REPO);
const deployStartedAt = new Date().toISOString();
let deployRecorded = false;

function recordDeploy(status, { exitCode = 0, error = null, activityMessage = null } = {}) {
  if (deployRecorded) return;
  deployRecorded = true;
  recordDirectDeployOutcome({
    repo: DEPLOY_REPO,
    label: deployTarget?.label,
    npmScript: DEPLOY_NPM_SCRIPT,
    status,
    startedAt: deployStartedAt,
    exitCode,
    error,
    activityMessage,
  });
}

function run(command, args, options = {}) {
  const r = spawnSync(command, args, {
    stdio: "inherit",
    cwd: options.cwd || root,
    shell,
    env: { ...process.env, ...options.env },
  });
  if (r.error) throw r.error;
  if (r.status !== 0) {
    recordDeploy("failure", {
      exitCode: r.status ?? 1,
      error: `${command} exited ${r.status ?? 1}`,
    });
    process.exit(r.status ?? 1);
  }
}

function runGit(args) {
  const r = spawnSync("git", args, {
    cwd: root,
    encoding: "utf8",
    shell,
  });
  if (r.status !== 0) return "";
  return (r.stdout || "").trim();
}

function getHeadCommit() {
  return runGit(["rev-parse", "HEAD"]);
}

function hasWorkingTreeChanges() {
  return Boolean(runGit(["status", "--porcelain"]));
}

const POST_RELEASE_SYNC_PATTERN = /^Sync Xcode project after v\d+\.\d+\.\d+ release/i;

function isPostReleaseSyncOnly(commits) {
  if (commits.length === 0) return false;
  return commits.every((commit) => {
    const subject = commit.subject.trim();
    return isMetaCommit(subject) || POST_RELEASE_SYNC_PATTERN.test(subject);
  });
}

function isDeployCheckpointOnlyChange(changedFiles) {
  if (!changedFiles.length) return true;
  return changedFiles.every((file) => {
    if (file.startsWith("scripts/")) return true;
    if (file.startsWith("release-notes/")) return true;
    if (file.startsWith("logs/")) return true;
    if (file === "package.json") return true;
    if (file === "app/project.yml") return true;
    if (file === "app/DiskWise/Info.plist") return true;
    if (file.startsWith("app/DiskWise.xcodeproj/")) return true;
    if (file.startsWith("app/DiskWise/Assets.xcassets/")) return true;
    return false;
  });
}

async function syncPublishedReleaseCheckpoint({
  appId,
  headCommit,
  version,
  reason,
}) {
  console.log(`release: skip — ${reason}`);
  try {
    await markReleaseCheckpoint(appId, headCommit, version);
  } catch (err) {
    console.warn(`release: could not update Firestore checkpoint (${err.message})`);
  }
  recordDeploy("success", {
    exitCode: 0,
    activityMessage: `deploy synced at HEAD — v${version} already published (${reason})`,
  });
}

function getCommitsSince(sinceCommit) {
  if (!sinceCommit) {
    const output = runGit(["log", "HEAD", "--pretty=format:%H|%s|%an"]);
    if (!output) return [];
    return output.split("\n").filter(Boolean).map((line) => {
      const [hash, subject, author] = line.split("|");
      return { hash, subject: subject || "", author: author || "" };
    });
  }

  const range = `${sinceCommit}..HEAD`;
  const count = runGit(["rev-list", "--count", range]);
  if (count === "0") return [];
  return getCommits(range);
}

function readPackageJson() {
  return JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
}

function writePackageVersion(version) {
  const pkg = readPackageJson();
  pkg.version = version;
  fs.writeFileSync(packageJsonPath, `${JSON.stringify(pkg, null, 2)}\n`, "utf8");
  console.log(`release: set package.json version → ${version}`);
}

function resolveNextVersion(lastReleasedVersion, commits) {
  const baseVersion = lastReleasedVersion || readPackageJson().version;
  assertSemver(baseVersion, "base version");
  const bump = suggestBumpLevel(commits);
  return { version: bumpSemver(baseVersion, bump), bump };
}

function getGitReleaseState() {
  const tag = runGit(["describe", "--tags", "--abbrev=0", "--match", "v*"]);
  if (!tag) return null;
  const version = tag.replace(/^v/, "");
  const commit = runGit(["rev-list", "-n", "1", tag]);
  if (!commit) return null;
  return { lastReleasedCommit: commit, lastReleasedVersion: version, source: "git-tag" };
}

function createGitTag(version) {
  if (process.env.RELEASE_SKIP_TAG === "1") return;
  const tag = `v${version}`;
  const existing = runGit(["tag", "--list", tag]);
  if (existing) {
    console.log(`release: git tag ${tag} already exists`);
    return;
  }
  run("git", ["tag", "-a", tag, "-m", `Release ${tag}`]);
  console.log(`release: created git tag ${tag}`);
}

async function main() {
  loadDotenv(root);
  // Production releases must never use local Sparkle/download URLs from .env.example.
  process.env.SPARKLE_LOCAL = "0";
  process.env.LOCAL_RELEASE = "0";

  const pkg = readPackageJson();
  if (!pkg.version) {
    console.error("release: package.json is missing a version field");
    process.exit(1);
  }

  const appId = resolveAppId(pkg);
  const headCommit = getHeadCommit();
  if (!headCommit) {
    console.error("release: not a git repository or unable to read HEAD");
    process.exit(1);
  }

  let releaseState = await getLatestPluginRelease(appId);
  if (!releaseState.lastReleasedCommit) {
    const gitState = getGitReleaseState();
    if (gitState) {
      releaseState = { ...releaseState, ...gitState };
      console.log(
        `release: using ${gitState.source} checkpoint v${gitState.lastReleasedVersion} (${gitState.lastReleasedCommit.slice(0, 7)})`
      );
    }
  } else if (releaseState.source === "firestore") {
    console.log(
      `release: using firestore checkpoint v${releaseState.lastReleasedVersion} (${releaseState.lastReleasedCommit.slice(0, 7)})`
    );
  }

  const lastCommit = releaseState.lastReleasedCommit;
  const commitsSinceLast = getCommitsSince(lastCommit);
  const dirty = hasWorkingTreeChanges();
  const force = process.env.RELEASE_FORCE === "1";

  if (
    !force &&
    lastCommit &&
    headCommit === lastCommit &&
    commitsSinceLast.length === 0 &&
    !dirty
  ) {
    await syncPublishedReleaseCheckpoint({
      appId,
      headCommit,
      version: releaseState.lastReleasedVersion || pkg.version,
      reason: `no code changes since last release (${lastCommit.slice(0, 7)})`,
    });
    return;
  }

  if (
    !force &&
    lastCommit &&
    releaseState.lastReleasedVersion &&
    isPostReleaseSyncOnly(commitsSinceLast)
  ) {
    await syncPublishedReleaseCheckpoint({
      appId,
      headCommit,
      version: releaseState.lastReleasedVersion,
      reason: "post-release Xcode sync only",
    });
    return;
  }

  const changeRange = lastCommit ? `${lastCommit}..HEAD` : "HEAD";
  const changedFiles = getChangedFiles(changeRange);
  if (
    !force &&
    lastCommit &&
    releaseState.lastReleasedVersion &&
    isDeployCheckpointOnlyChange(changedFiles)
  ) {
    await syncPublishedReleaseCheckpoint({
      appId,
      headCommit,
      version: releaseState.lastReleasedVersion,
      reason: `v${releaseState.lastReleasedVersion} already published (deploy checkpoint only)`,
    });
    return;
  }

  let version;
  const releaseVersionOverride = process.env.RELEASE_VERSION?.trim();
  if (releaseVersionOverride) {
    version = releaseVersionOverride;
    assertSemver(version, "RELEASE_VERSION");
    writePackageVersion(version);
    console.log(`release: using RELEASE_VERSION override → v${version}`);
  } else if (!releaseState.lastReleasedVersion) {
    version = pkg.version;
    assertSemver(version, "package.json version");
    console.log(`release: first release at v${version} (${headCommit.slice(0, 7)})`);
  } else {
    const next = resolveNextVersion(releaseState.lastReleasedVersion, commitsSinceLast);
    version = next.version;
    writePackageVersion(version);
    console.log(
      `release: ${commitsSinceLast.length} commit(s) since ${lastCommit?.slice(0, 7) || "?"} — ${next.bump} bump → v${version}`
    );
  }

  syncAppVersion(version);

  const releasesDir = path.join(root, "releases");
  fs.mkdirSync(releasesDir, { recursive: true });
  const dmgPath = path.join(releasesDir, dmgFileName(appId, version));

  console.log("release: building signed + notarized DMG…");
  run("bash", ["scripts/release.sh"], {
    env: {
      OUTPUT_DMG: dmgPath,
      SPARKLE_LOCAL: "0",
    },
  });

  await uploadRelease({
    version,
    dmgPath,
    sinceCommit: lastCommit,
    previousVersion: releaseState.lastReleasedVersion,
  });

  await markReleaseCheckpoint(appId, headCommit, version);
  createGitTag(version);

  console.log(`release: done — v${version} (${headCommit.slice(0, 7)})`);
  console.log(`release: artifact ${dmgPath}`);
  recordDeploy("success", {
    exitCode: 0,
    activityMessage: `release: done — v${version} (${headCommit.slice(0, 7)})`,
  });
}

main().catch((err) => {
  recordDeploy("failure", { exitCode: 1, error: err.message || String(err) });
  console.error(err);
  process.exit(1);
});
