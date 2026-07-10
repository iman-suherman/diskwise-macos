#!/usr/bin/env node
/**
 * Build .env from .env.example and Cloud Secret Manager (CSM).
 */
const path = require("path");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
const { parseEnvFile, resolveGcpProjectId } = require("./gcp-config.cjs");
const { resolveAdcPath } = require("./gcp-lib-adc.cjs");
const { generateEnv } = require("./csm-secrets.cjs");

const repoRoot = path.join(__dirname, "..");

function main() {
  const force = process.argv.includes("--force");
  try {
    generateEnv({
      parseEnvFile: (filePath) => parseEnvFile(filePath),
      applyGcpEnv,
      resolveGcpProjectId: () => resolveGcpProjectId(repoRoot),
      resolveAdcPath: (root, opts) => resolveAdcPath(root, opts),
      force,
    });
  } catch (error) {
    console.error(`generate-env: ${error.message}`);
    process.exit(1);
  }
}

main();
