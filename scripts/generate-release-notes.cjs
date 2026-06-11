/**
 * Build structured release notes from git history since the previous release.
 */
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const { assertSemver, parseSemver } = require("./semver.cjs");

const root = path.join(__dirname, "..");
const shell = process.platform === "win32";

function runGit(args) {
  const r = spawnSync("git", args, {
    cwd: root,
    encoding: "utf8",
    shell,
  });
  if (r.status !== 0) return "";
  return (r.stdout || "").trim();
}

function getPreviousTag(currentVersion) {
  const output = runGit(["tag", "--list", "v*", "--sort=-v:refname"]);
  const tags = output.split("\n").map((tag) => tag.trim()).filter(Boolean);
  for (const tag of tags) {
    const tagVersion = tag.replace(/^v/, "");
    if (tagVersion !== currentVersion) return tag;
  }
  return null;
}

function getCommitRange(previousTag, sinceCommit) {
  if (sinceCommit) return `${sinceCommit}..HEAD`;
  if (previousTag) return `${previousTag}..HEAD`;
  const firstCommit = runGit(["rev-list", "--max-parents=0", "HEAD"]);
  return firstCommit ? `${firstCommit}..HEAD` : "HEAD";
}

function getCommits(range) {
  const output = runGit(["log", range, "--pretty=format:%H|%s|%an"]);
  if (!output) return [];
  return output.split("\n").filter(Boolean).map((line) => {
    const [hash, subject, author] = line.split("|");
    return { hash, subject: subject || "", author: author || "" };
  });
}

function categorizeCommit(subject) {
  const text = subject.trim();
  const breaking = /!:|BREAKING CHANGE/i.test(text);
  const conventional = text.match(/^(\w+)(?:\([^)]+\))?!?:\s*(.+)$/);

  if (!conventional) {
    return { category: "changed", summary: text, breaking: false };
  }

  const type = conventional[1].toLowerCase();
  const summary = conventional[2].trim();
  const isBreaking = breaking || text.includes("!");

  if (isBreaking) {
    return { category: "breaking", summary, breaking: true };
  }

  switch (type) {
    case "feat":
      return { category: "introduced", summary, breaking: false };
    case "fix":
      return { category: "fixed", summary, breaking: false };
    case "perf":
    case "refactor":
      return { category: "changed", summary, breaking: false };
    case "docs":
    case "chore":
    case "build":
    case "ci":
    case "style":
    case "test":
      return { category: "updated", summary, breaking: false };
    case "remove":
    case "removed":
      return { category: "removed", summary, breaking: false };
    default:
      return { category: "changed", summary: text, breaking: false };
  }
}

function uniqueItems(items) {
  return [...new Set(items.filter(Boolean))];
}

function suggestBumpLevel(commits) {
  let bump = "patch";
  for (const commit of commits) {
    const { category, breaking } = categorizeCommit(commit.subject);
    if (breaking || category === "breaking") return "major";
    if (category === "introduced" && bump !== "major") bump = "minor";
  }
  return bump;
}

function buildMarkdown(version, releaseNotes, previousLabel) {
  const lines = [`# DiskWise ${version}`, ""];
  if (previousLabel) {
    lines.push(`Changes since \`${previousLabel}\`.`, "");
  } else {
    lines.push("Initial tracked release.", "");
  }

  const sections = [
    ["Breaking changes", releaseNotes.breaking],
    ["Introduced", releaseNotes.introduced],
    ["Changed", releaseNotes.changed],
    ["Updated", releaseNotes.updated],
    ["Fixed", releaseNotes.fixed],
    ["Removed", releaseNotes.removed],
  ];

  for (const [title, items] of sections) {
    if (!items.length) continue;
    lines.push(`## ${title}`, "");
    for (const item of items) {
      lines.push(`- ${item}`);
    }
    lines.push("");
  }

  if (releaseNotes.summary) {
    lines.push("## Summary", "", releaseNotes.summary, "");
  }

  return `${lines.join("\n").trim()}\n`;
}

function resolveReleaseNotesOverride() {
  if (process.env.RELEASE_NOTES?.trim()) {
    return process.env.RELEASE_NOTES.trim();
  }
  const notesFile = process.env.RELEASE_NOTES_FILE?.trim();
  if (notesFile && fs.existsSync(notesFile)) {
    return fs.readFileSync(notesFile, "utf8").trim();
  }
  const defaultNotes = path.join(root, "RELEASE_NOTES.md");
  if (fs.existsSync(defaultNotes)) {
    return fs.readFileSync(defaultNotes, "utf8").trim();
  }
  return null;
}

function generateReleaseNotes(options = {}) {
  const packageJson = require(path.join(root, "package.json"));
  const version = options.version || packageJson.version;
  const pluginId =
    options.pluginId ||
    process.env.DEFAULT_APP_ID?.trim() ||
    packageJson.name;
  const displayName = options.displayName || packageJson.displayName || "DiskWise";

  const parsed = assertSemver(version, "package.json version");
  const sinceCommit = options.sinceCommit || null;
  const previousTag = sinceCommit ? null : options.previousTag ?? getPreviousTag(version);
  const previousLabel =
    options.previousLabel || (sinceCommit ? sinceCommit.slice(0, 7) : previousTag);
  const range = getCommitRange(previousTag, sinceCommit);
  const commits = getCommits(range);

  const releaseNotes = {
    introduced: [],
    changed: [],
    updated: [],
    fixed: [],
    removed: [],
    breaking: [],
  };

  for (const commit of commits) {
    const { category, summary } = categorizeCommit(commit.subject);
    releaseNotes[category].push(summary);
  }

  for (const key of Object.keys(releaseNotes)) {
    releaseNotes[key] = uniqueItems(releaseNotes[key]);
  }

  const headlineParts = [];
  if (releaseNotes.introduced.length) headlineParts.push(`${releaseNotes.introduced.length} new`);
  if (releaseNotes.changed.length) headlineParts.push(`${releaseNotes.changed.length} changed`);
  if (releaseNotes.fixed.length) headlineParts.push(`${releaseNotes.fixed.length} fixed`);

  const summary =
    headlineParts.length > 0
      ? `${displayName} ${version}: ${headlineParts.join(", ")}.`
      : `${displayName} ${version} release.`;

  const overrideMarkdown = resolveReleaseNotesOverride();
  const gitCommit = runGit(["rev-parse", "HEAD"]);

  return {
    pluginId,
    displayName,
    publisher: packageJson.publisher || "",
    version: parsed.version,
    semver: {
      major: parsed.major,
      minor: parsed.minor,
      patch: parsed.patch,
      prerelease: parsed.prerelease,
      build: parsed.build,
    },
    previousTag,
    sinceCommit,
    previousLabel,
    gitCommit,
    gitTag: `v${parsed.version}`,
    commitCount: commits.length,
    releaseNotes,
    summary,
    releaseNotesMarkdown:
      overrideMarkdown || buildMarkdown(parsed.version, releaseNotes, previousLabel),
    generatedAt: new Date().toISOString(),
  };
}

function writeReleaseArtifacts(release, outputDir = path.join(root, "releases")) {
  fs.mkdirSync(outputDir, { recursive: true });
  const jsonPath = path.join(outputDir, `release-${release.version}.json`);
  const mdPath = path.join(outputDir, `release-${release.version}.md`);
  fs.writeFileSync(jsonPath, `${JSON.stringify(release, null, 2)}\n`, "utf8");
  fs.writeFileSync(mdPath, release.releaseNotesMarkdown, "utf8");
  return { jsonPath, mdPath };
}

if (require.main === module) {
  const release = generateReleaseNotes();
  const paths = writeReleaseArtifacts(release);
  console.log("release-notes:", paths.jsonPath);
  console.log("release-notes:", paths.mdPath);
  console.log(release.summary);
}

module.exports = {
  generateReleaseNotes,
  writeReleaseArtifacts,
  categorizeCommit,
  suggestBumpLevel,
  getCommits,
};
