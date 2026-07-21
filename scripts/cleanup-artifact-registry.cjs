#!/usr/bin/env node
/**
 * List (and optionally delete) Artifact Registry Docker repositories
 * left over from Cloud Run --source deploys.
 *
 * Usage:
 *   npm run deploy:cleanup-ar           # dry-run
 *   npm run deploy:cleanup-ar -- --apply
 *   npm run deploy:cleanup-ar -- --repo cloud-run-source-deploy --apply
 */
const { spawnSync } = require("child_process");
const path = require("path");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
const { loadDotenv } = require("./load-dotenv.cjs");

const root = path.join(__dirname, "..");
const apply = process.argv.includes("--apply");
const repoFilterArg = process.argv.find((a, i) => process.argv[i - 1] === "--repo");
const locationFilter =
  process.argv.find((a, i) => process.argv[i - 1] === "--location") || "";

function runJson(command, args) {
  const r = spawnSync(command, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
  });
  if (r.status !== 0) {
    const err = (r.stderr || r.stdout || "").trim();
    throw new Error(`${command} ${args.join(" ")} failed: ${err || `exit ${r.status}`}`);
  }
  const out = (r.stdout || "").trim();
  if (!out) return [];
  try {
    return JSON.parse(out);
  } catch {
    return [];
  }
}

function main() {
  loadDotenv(root);
  applyGcpEnv(root);

  const projectId = resolveGcpProjectId(root);
  if (!projectId) {
    console.error("cleanup-artifact-registry: GCP_PROJECT_ID is not set. Run: npm run login");
    process.exit(1);
  }

  const location = locationFilter || process.env.GCP_LOCATION?.trim() || "australia-southeast1";
  console.log(`cleanup-artifact-registry: project=${projectId} location=${location}`);
  console.log(`cleanup-artifact-registry: mode=${apply ? "APPLY (delete)" : "dry-run"}`);

  const repos = runJson("gcloud", [
    "artifacts",
    "repositories",
    "list",
    `--project=${projectId}`,
    `--location=${location}`,
    "--format=json",
  ]);

  if (!Array.isArray(repos) || repos.length === 0) {
    console.log("cleanup-artifact-registry: no Artifact Registry repositories found");
    return;
  }

  const filtered = repos.filter((repo) => {
    const name = String(repo.name || "").split("/").pop();
    if (repoFilterArg) return name === repoFilterArg;
    return (
      name === "cloud-run-source-deploy" ||
      name.includes("cloud-run-source") ||
      name.includes("gcf-artifacts")
    );
  });

  if (filtered.length === 0) {
    console.log("cleanup-artifact-registry: no matching Cloud Run source repositories");
    console.log("  all repositories in location:");
    for (const repo of repos) {
      console.log(`    - ${String(repo.name || "").split("/").pop()} (${repo.format || "?"})`);
    }
    console.log("  Tip: npm run deploy:cleanup-ar -- --repo <name> --apply");
    return;
  }

  for (const repo of filtered) {
    const fullName = repo.name;
    const short = String(fullName || "").split("/").pop();
    const format = repo.format || "?";
    console.log(`\n==> ${short} (${format})`);
    console.log(`    ${fullName}`);

    if (!apply) {
      console.log("    dry-run: would delete this repository and all images");
      continue;
    }

    const del = spawnSync(
      "gcloud",
      [
        "artifacts",
        "repositories",
        "delete",
        short,
        `--project=${projectId}`,
        `--location=${location}`,
        "--quiet",
      ],
      { cwd: root, stdio: "inherit", env: process.env },
    );
    if (del.status !== 0) {
      console.error(`cleanup-artifact-registry: failed to delete ${short}`);
      process.exit(del.status ?? 1);
    }
    console.log(`    deleted ${short}`);
  }

  if (!apply) {
    console.log("\nRe-run with --apply to delete the repositories above.");
    console.log("After deletion, Artifact Registry storage charges should drop to ~$0.");
  } else {
    console.log("\ncleanup-artifact-registry: done");
  }
}

main();
