/**
 * One-time GCP + git-hooks setup for website deploy.
 * Runs: generate-env → login → install-hooks
 */
const path = require("path");
const { spawnSync } = require("child_process");
const { generateEnv } = require("./generate-env.cjs");

const root = path.join(__dirname, "..");
const shell = process.platform === "win32";

function runNpmScript(script) {
  const result = spawnSync("npm", ["run", script], {
    cwd: root,
    stdio: "inherit",
    shell,
    env: process.env,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function main() {
  console.log("\nsetup: step 1/3 — generate-env\n");
  const envResult = generateEnv(root, { quiet: true });
  if (envResult.created) {
    console.log("setup: created .env from .env.example");
  } else {
    console.log("setup: using existing .env");
  }

  console.log("\nsetup: step 2/3 — login (GCP browser sign-in)\n");
  runNpmScript("login");

  console.log("\nsetup: step 3/3 — install-hooks\n");
  runNpmScript("install-hooks");

  console.log("\nsetup: done — deploy with npm run deploy:website · track with npm run ci\n");
}

main();
