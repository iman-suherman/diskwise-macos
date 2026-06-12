const test = require("node:test");
const assert = require("node:assert/strict");
const {
  isMetaCommit,
  analyzeChanges,
  buildMarkdown,
  generateReleaseNotes,
} = require("./generate-release-notes.cjs");

test("isMetaCommit filters release pipeline messages", () => {
  assert.equal(isMetaCommit("Release 1.0.0: three-phase storage consultant workflow."), true);
  assert.equal(isMetaCommit("Release v0.2.4 with faster post-What's New startup."), true);
  assert.equal(isMetaCommit("Re-release as 0.3.0 with update-first post-upgrade flow."), true);
  assert.equal(isMetaCommit("Allow RELEASE_VERSION override in publish pipeline."), true);
  assert.equal(isMetaCommit("feat: add APFS snapshot thinning"), false);
});

test("analyzeChanges produces friendly bullets from paths", () => {
  const notes = analyzeChanges([
    "app/DiskWise/AppViewModel.swift",
    "Sources/MaintenanceKit/APFSSnapshotScanner.swift",
    "app/DiskWise/SparkleUpdater.swift",
  ]);

  assert.ok(notes.introduced.some((item) => item.includes("three-step")));
  assert.ok(notes.introduced.some((item) => item.includes("APFS Snapshot")));
  assert.ok(notes.changed.some((item) => item.includes("What's New")));
});

test("curated 0.3.0 notes avoid meta commit language", () => {
  const release = generateReleaseNotes({ version: "0.3.0" });

  const flat = [
    ...release.releaseNotes.introduced,
    ...release.releaseNotes.changed,
    ...release.releaseNotes.fixed,
  ];

  assert.ok(release.summary.includes("storage consultant"));
  assert.ok(flat.some((item) => item.includes("Three-phase")));
  assert.ok(!flat.some((item) => /Release v?\d|Re-release|RELEASE_VERSION/i.test(item)));
});

test("markdown uses friendly section titles", () => {
  const md = buildMarkdown(
    "0.3.0",
    {
      introduced: ["Duplicate finder moved to its own tab"],
      changed: [],
      updated: [],
      fixed: [],
      removed: [],
      breaking: [],
    },
    "v0.2.4",
    "DiskWise 0.3.0 — a storage consultant for your Mac."
  );

  assert.match(md, /## What's new/);
  assert.doesNotMatch(md, /Release 1\.0\.0/);
});
