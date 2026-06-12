/**
 * Build user-facing release notes from the previous semver tag, curated files,
 * and (when needed) code-change analysis — never raw release/meta commit messages.
 */
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const { assertSemver, parseSemver, compareSemver } = require("./semver.cjs");

const root = path.join(__dirname, "..");
const curatedDir = path.join(root, "release-notes");
const shell = process.platform === "win32";

const META_COMMIT_PATTERNS = [
  /^Release v?\d/i,
  /^Re-release /i,
  /^Allow RELEASE_VERSION/i,
  /^Merge /i,
  /^Merge branch /i,
  /^Bump version/i,
  /^chore(\([^)]*\))?!?: (release|bump|version)/i,
  /^sync version/i,
  /^publish release/i,
];

const SECTION_LABELS = {
  breaking: "Important changes",
  introduced: "What's new",
  changed: "Improvements",
  updated: "Under the hood",
  fixed: "Fixes",
  removed: "Removed",
};

function runGit(args) {
  const r = spawnSync("git", args, {
    cwd: root,
    encoding: "utf8",
    shell,
  });
  if (r.status !== 0) return "";
  return (r.stdout || "").trim();
}

function getAllVersionTags() {
  const output = runGit(["tag", "--list", "v*", "--sort=-v:refname"]);
  return output
    .split("\n")
    .map((tag) => tag.trim())
    .filter(Boolean)
    .map((tag) => ({ tag, version: tag.replace(/^v/, "") }))
    .filter(({ version }) => parseSemver(version));
}

/** Highest semver tag strictly less than `currentVersion`. */
function getPreviousReleaseTag(currentVersion) {
  const current = parseSemver(currentVersion);
  if (!current) return null;

  for (const { tag, version } of getAllVersionTags()) {
    const parsed = parseSemver(version);
    if (parsed && compareSemver(parsed, current) < 0) {
      return tag;
    }
  }
  return null;
}

function getCommitRange(previousTag) {
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

function getChangedFiles(range) {
  const output = runGit(["diff", range, "--name-only", "--diff-filter=ACDMRT"]);
  if (!output) return [];
  return output.split("\n").filter(Boolean);
}

function isMetaCommit(subject) {
  const text = subject.trim();
  if (!text) return true;
  return META_COMMIT_PATTERNS.some((pattern) => pattern.test(text));
}

function humanizeCommitSummary(subject) {
  const text = subject.trim();
  const conventional = text.match(/^(\w+)(?:\([^)]+\))?!?:\s*(.+)$/);
  if (!conventional) return null;

  const type = conventional[1].toLowerCase();
  const summary = conventional[2].trim();
  if (isMetaCommit(text)) return null;

  const skipTypes = new Set(["chore", "build", "ci", "style", "test", "docs"]);
  if (skipTypes.has(type)) return null;

  if (!summary) return null;
  return summary.charAt(0).toUpperCase() + summary.slice(1);
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

function emptyReleaseNotes() {
  return {
    introduced: [],
    changed: [],
    updated: [],
    fixed: [],
    removed: [],
    breaking: [],
  };
}

function mergeReleaseNotes(base, extra) {
  const merged = emptyReleaseNotes();
  for (const key of Object.keys(merged)) {
    merged[key] = uniqueItems([...(base[key] || []), ...(extra[key] || [])]);
  }
  return merged;
}

/** Infer user-facing bullets from changed paths when no curated notes exist. */
function analyzeChanges(files) {
  const notes = emptyReleaseNotes();
  const paths = files.join("\n");

  const signals = [
    {
      category: "introduced",
      match: /AppViewModel|ScanPhase|ActionBucket|DashboardView/,
      text: "A clearer three-step flow: identify what's using space, analyze findings, then act on recommendations",
    },
    {
      category: "introduced",
      match: /MaintenanceKit|MaintenanceView|MaintenanceKind/,
      text: "Individual Maintenance tools for caches, node_modules, installers, APFS snapshots, and more",
    },
    {
      category: "introduced",
      match: /APFSSnapshot|APFS/,
      text: "APFS Snapshot thinning when deleted files still don't free space",
    },
    {
      category: "introduced",
      match: /IndexRebuildOverlay|needsIndexRebuild/,
      text: "Option to rebuild your storage index after a major scan-model upgrade",
    },
    {
      category: "changed",
      match: /SparkleUpdater|schedulePostUpgradePresentation|WhatsNewTour/,
      text: "Smoother first launch after updating — checks for updates, then shows What's New",
    },
    {
      category: "changed",
      match: /DuplicatesView|DuplicateEngine/,
      text: "Duplicate detection runs from the Duplicates tab when you choose, not during every scan",
    },
    {
      category: "fixed",
      match: /fix|Fix|bug/,
      text: null,
    },
  ];

  for (const signal of signals) {
    if (signal.text && signal.match.test(paths)) {
      notes[signal.category].push(signal.text);
    }
  }

  for (const key of Object.keys(notes)) {
    notes[key] = uniqueItems(notes[key]);
  }
  return notes;
}

function loadCuratedNotes(version) {
  const jsonPath = path.join(curatedDir, `${version}.json`);
  if (!fs.existsSync(jsonPath)) return null;

  const raw = JSON.parse(fs.readFileSync(jsonPath, "utf8"));
  const notes = emptyReleaseNotes();
  for (const key of Object.keys(notes)) {
    notes[key] = uniqueItems(raw[key] || []);
  }
  return {
    summary: raw.summary?.trim() || null,
    notes,
  };
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

function buildSummary(displayName, version, releaseNotes, curatedSummary) {
  if (curatedSummary) return curatedSummary;

  const lead =
    releaseNotes.introduced[0] ||
    releaseNotes.changed[0] ||
    releaseNotes.fixed[0] ||
    null;

  if (lead) {
    return `${displayName} ${version} — ${lead.charAt(0).toLowerCase()}${lead.slice(1)}`;
  }

  return `${displayName} ${version} — improvements and fixes.`;
}

function buildMarkdown(version, releaseNotes, previousTag, summary) {
  const previousVersion = previousTag ? previousTag.replace(/^v/, "") : null;
  const lines = [`# DiskWise ${version}`, ""];

  if (previousVersion) {
    lines.push(`What's new since **${previousVersion}**.`, "");
  } else {
    lines.push(`What's new in DiskWise **${version}**.`, "");
  }

  if (summary) {
    lines.push(summary, "");
  }

  const sections = [
    ["breaking", releaseNotes.breaking],
    ["introduced", releaseNotes.introduced],
    ["changed", releaseNotes.changed],
    ["fixed", releaseNotes.fixed],
    ["updated", releaseNotes.updated],
    ["removed", releaseNotes.removed],
  ];

  for (const [key, items] of sections) {
    if (!items.length) continue;
    lines.push(`## ${SECTION_LABELS[key]}`, "");
    for (const item of items) {
      lines.push(`- ${item}`);
    }
    lines.push("");
  }

  return `${lines.join("\n").trim()}\n`;
}

function suggestBumpLevel(commits) {
  let bump = "patch";
  for (const commit of commits) {
    if (isMetaCommit(commit.subject)) continue;
    const { category, breaking } = categorizeCommit(commit.subject);
    if (breaking || category === "breaking") return "major";
    if (category === "introduced" && bump !== "major") bump = "minor";
  }
  return bump;
}

function generateReleaseNotes(options = {}) {
  const packageJson = require(path.join(root, "package.json"));
  const version = options.version || packageJson.version;
  const pluginId =
    options.pluginId || process.env.DEFAULT_APP_ID?.trim() || packageJson.name;
  const displayName = options.displayName || packageJson.displayName || "DiskWise";

  const parsed = assertSemver(version, "package.json version");
  const previousTag = options.previousTag ?? getPreviousReleaseTag(version);
  const previousLabel = options.previousLabel || previousTag || "initial release";
  const notesRange = getCommitRange(previousTag);
  const commits = getCommits(notesRange);
  const changedFiles = getChangedFiles(notesRange);

  const curated = loadCuratedNotes(parsed.version);
  let releaseNotes = emptyReleaseNotes();
  let curatedSummary = null;

  if (curated) {
    releaseNotes = curated.notes;
    curatedSummary = curated.summary;
  } else {
    releaseNotes = analyzeChanges(changedFiles);

    for (const commit of commits) {
      if (isMetaCommit(commit.subject)) continue;
      const human = humanizeCommitSummary(commit.subject);
      if (human) {
        const { category } = categorizeCommit(commit.subject);
        releaseNotes[category].push(human);
      }
    }

    for (const key of Object.keys(releaseNotes)) {
      releaseNotes[key] = uniqueItems(releaseNotes[key]);
    }
  }

  const summary = buildSummary(displayName, parsed.version, releaseNotes, curatedSummary);
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
    previousLabel,
    gitCommit,
    gitTag: `v${parsed.version}`,
    commitCount: commits.filter((c) => !isMetaCommit(c.subject)).length,
    releaseNotes,
    summary,
    releaseNotesMarkdown:
      overrideMarkdown ||
      buildMarkdown(parsed.version, releaseNotes, previousTag, summary),
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
  getPreviousReleaseTag,
  isMetaCommit,
  analyzeChanges,
  buildMarkdown,
  SECTION_LABELS,
};
