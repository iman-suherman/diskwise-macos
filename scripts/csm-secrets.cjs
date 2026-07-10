/**
 * Cloud Secret Manager (CSM) helpers for DiskWise.
 */
const path = require("path");
const { createCsmSecrets } = require("./csm-repo-env.cjs");

const repoRoot = path.join(__dirname, "..");

const MANAGED_SECRETS = [
  "GCP_USER_EMAIL",
  "GCP_PROJECT_ID",
  "SPARKLE_PRIVATE_KEY",
];

const MANAGED_FILE_SECRETS = [];

const csm = createCsmSecrets(repoRoot, {
  managedSecrets: MANAGED_SECRETS,
  managedFileSecrets: MANAGED_FILE_SECRETS,
});

module.exports = {
  MANAGED_SECRETS,
  MANAGED_FILE_SECRETS,
  ...csm,
};
