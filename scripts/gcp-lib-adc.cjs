/**
 * Project-local Application Default Credentials (ADC).
 * gcloud always writes ADC to the user config dir first; we copy into .gcloud/
 * so this repo does not rely on mixing with other projects' workflows.
 */
const fs = require("fs");
const os = require("os");
const path = require("path");

const ADC_FILENAME = "application_default_credentials.json";

function getDefaultAdcPath() {
  if (process.platform === "win32") {
    const base = process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming");
    return path.join(base, "gcloud", ADC_FILENAME);
  }
  return path.join(os.homedir(), ".config", "gcloud", ADC_FILENAME);
}

function getProjectAdcPath(repoRoot) {
  return path.join(repoRoot, ".gcloud", ADC_FILENAME);
}

/**
 * Copy ADC from gcloud's global location into repo .gcloud/
 */
function syncAdcToProject(repoRoot) {
  const src = getDefaultAdcPath();
  const dest = getProjectAdcPath(repoRoot);

  if (!fs.existsSync(src)) {
    console.error(
      "gcp-sync-adc: no ADC file at",
      src,
      "\nRun: npm run login"
    );
    return false;
  }

  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
  console.log("gcp-sync-adc: copied ADC to", dest);
  return true;
}

module.exports = {
  ADC_FILENAME,
  getDefaultAdcPath,
  getProjectAdcPath,
  syncAdcToProject,
};
