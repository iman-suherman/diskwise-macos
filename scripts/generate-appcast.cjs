/**
 * Generate Sparkle appcast.xml from signed ZIP archives in releases/sparkle/.
 */
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const { loadDotenv } = require("./load-dotenv.cjs");
const { resolveDownloadBase } = require("./public-download-url.cjs");
const { SECTION_LABELS } = require("./generate-release-notes.cjs");

const root = path.join(__dirname, "..");
const shell = process.platform === "win32";

function run(command, args, options = {}) {
  const r = spawnSync(command, args, {
    stdio: "inherit",
    cwd: options.cwd || root,
    shell,
    env: { ...process.env, ...options.env },
  });
  if (r.error) throw r.error;
  if (r.status !== 0) process.exit(r.status ?? 1);
}

function sparkleReleaseNotesHtml(release) {
  const lines = ["<ul>"];
  const sections = [
    ["breaking", release.releaseNotes.breaking],
    ["introduced", release.releaseNotes.introduced],
    ["changed", release.releaseNotes.changed],
    ["fixed", release.releaseNotes.fixed],
    ["updated", release.releaseNotes.updated],
    ["removed", release.releaseNotes.removed],
  ];

  for (const [key, items] of sections) {
    if (!items?.length) continue;
    const title = SECTION_LABELS[key] || key;
    lines.push(`<li><strong>${title}</strong><ul>`);
    for (const item of items) {
      lines.push(`<li>${item}</li>`);
    }
    lines.push("</ul></li>");
  }

  if (lines.length === 1 && release.summary) {
    lines.push(`<li>${release.summary}</li>`);
  }

  lines.push("</ul>");
  return `${lines.join("\n")}\n`;
}

function generateAppcast(options = {}) {
  loadDotenv(root);

  const archivesDir = options.archivesDir || path.join(root, "releases", "sparkle");
  const downloadBase = (options.downloadBase || resolveDownloadBase()).replace(/\/$/, "");
  const websiteAppcast = path.join(root, "website", "public", "appcast.xml");
  const releasesAppcast = path.join(archivesDir, "appcast.xml");

  fs.mkdirSync(archivesDir, { recursive: true });

  if (options.release) {
    const version = options.release.version;
    const htmlPath = path.join(archivesDir, `DiskWise-${version}.html`);
    fs.writeFileSync(htmlPath, sparkleReleaseNotesHtml(options.release), "utf8");
    console.log(`appcast: release notes → ${htmlPath}`);
  }

  run("bash", ["scripts/sparkle-tools.sh"], { cwd: root });

  const sparkleBin = path.join(root, ".sparkle-tools", "bin", "generate_appcast");
  const genArgs = [
    "--download-url-prefix",
    `${downloadBase}/`,
    "--embed-release-notes",
    "-o",
    releasesAppcast,
    archivesDir,
  ];

  if (options.channel) {
    genArgs.splice(0, 0, "--channel", options.channel);
  }

  run(sparkleBin, genArgs, { cwd: root });

  if (fs.existsSync(releasesAppcast)) {
    const copyToWebsite =
      options.copyToWebsite ??
      (process.env.SPARKLE_LOCAL === "1" || process.env.LOCAL_RELEASE === "1");
    if (copyToWebsite) {
      fs.mkdirSync(path.dirname(websiteAppcast), { recursive: true });
      fs.copyFileSync(releasesAppcast, websiteAppcast);
      console.log(`appcast: copied → ${websiteAppcast} (local website)`);
    } else {
      console.log(`appcast: skipped website copy — production feed served by registry API from GCS`);
    }
  }

  return {
    archivesDir,
    appcastPath: releasesAppcast,
    websiteAppcastPath: websiteAppcast,
  };
}

if (require.main === module) {
  const releasePath = process.argv[2];
  const release = releasePath ? JSON.parse(fs.readFileSync(releasePath, "utf8")) : null;
  generateAppcast({ release });
}

module.exports = { generateAppcast, sparkleReleaseNotesHtml };
