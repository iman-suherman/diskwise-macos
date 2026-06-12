/**
 * Regenerate and publish release notes for every curated version.
 *
 * Usage: node scripts/republish-all-notes.cjs [--dry-run]
 */
const fs = require("fs");
const path = require("path");
const { compareSemver, parseSemver } = require("./semver.cjs");
const { republishNotes } = require("./republish-notes.cjs");

const root = path.join(__dirname, "..");
const curatedDir = path.join(root, "release-notes");
const dryRun = process.argv.includes("--dry-run");

function listCuratedVersions() {
  return fs
    .readdirSync(curatedDir)
    .filter((name) => name.endsWith(".json"))
    .map((name) => name.replace(/\.json$/, ""))
    .filter((version) => parseSemver(version))
    .sort((a, b) => compareSemver(parseSemver(a), parseSemver(b)));
}

async function republishAllNotes() {
  const versions = listCuratedVersions();
  if (versions.length === 0) {
    console.error("republish-all-notes: no curated release-notes/*.json files found");
    process.exit(1);
  }

  console.log(`republish-all-notes: ${versions.length} version(s)${dryRun ? " (dry run)" : ""}`);
  for (const version of versions) {
    console.log(`\n--- ${version} ---`);
    if (dryRun) {
      console.log(`republish-all-notes: would republish ${version}`);
      continue;
    }
    await republishNotes(version);
  }
  console.log("\nrepublish-all-notes: done");
}

if (require.main === module) {
  republishAllNotes().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { republishAllNotes, listCuratedVersions };
