#!/usr/bin/env node
/**
 * Push managed secret values from .env into Cloud Secret Manager (CSM).
 */
const path = require("path");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
const { loadDotenv } = require("./load-dotenv.cjs");
const { seedSecrets } = require("./csm-secrets.cjs");

const repoRoot = path.join(__dirname, "..");

function main() {
  try {
    seedSecrets({
      loadDotenv: () => loadDotenv(repoRoot),
      applyGcpEnv: () => applyGcpEnv(repoRoot),
      allowEmpty: true,
    });
  } catch (error) {
    console.error(`seed-secrets: ${error.message}`);
    process.exit(1);
  }
}

main();
