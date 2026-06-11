/**
 * Merge .env.example then .env into process.env (repo root).
 */
const path = require("path");
const { parseEnvFile } = require("./gcp-config.cjs");

function loadDotenv(repoRoot) {
  const example = parseEnvFile(path.join(repoRoot, ".env.example"));
  const dotEnv = parseEnvFile(path.join(repoRoot, ".env"));
  const merged = { ...example, ...dotEnv };
  for (const [key, value] of Object.entries(merged)) {
    if (process.env[key] === undefined || process.env[key] === "") {
      process.env[key] = value;
    }
  }
  return merged;
}

module.exports = { loadDotenv };
