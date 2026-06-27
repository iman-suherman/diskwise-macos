const { loadDotenv } = require("./load-dotenv.cjs");
const { buildGcpCliEnv } = require("./gcp-config.cjs");

function applyGcpEnv(repoRoot) {
  loadDotenv(repoRoot);
  const env = buildGcpCliEnv(repoRoot);
  Object.assign(process.env, env);
  return env;
}

module.exports = { applyGcpEnv };
