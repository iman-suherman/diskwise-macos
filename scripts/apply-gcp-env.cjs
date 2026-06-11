const fs = require("fs");
const path = require("path");
const { loadDotenv } = require("./load-dotenv.cjs");
const { getProjectAdcPath } = require("./gcp-lib-adc.cjs");

function applyGcpEnv(repoRoot) {
  loadDotenv(repoRoot);

  const projectAdc = getProjectAdcPath(repoRoot);
  if (fs.existsSync(projectAdc)) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = projectAdc;
    return;
  }

  const configured = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!configured) return;

  const resolved = path.isAbsolute(configured)
    ? configured
    : path.join(repoRoot, configured);
  if (fs.existsSync(resolved)) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = resolved;
  }
}

module.exports = { applyGcpEnv };
