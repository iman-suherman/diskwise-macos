/**
 * Background worker invoked from the post-commit hook.
 * Deploys the marketing website when the latest commit touches website/.
 */
const {
  commitTouchesWebsite,
  getCommitFiles,
  isDeployConfigured,
  scheduleWebsiteDeploy,
  DEPLOY_TARGET,
} = require("./website-deploy-worker.cjs");

const logPrefix = "post-commit-website";

function main() {
  if (process.env.DISKWise_POST_COMMIT_WEBSITE === "0") {
    console.log(`${logPrefix}: disabled (DISKWise_POST_COMMIT_WEBSITE=0)`);
    return;
  }

  const files = getCommitFiles("HEAD");
  if (!commitTouchesWebsite(files)) {
    console.log(`${logPrefix}: skip — commit has no website/ changes`);
    return;
  }

  console.log(`${logPrefix}: website changes detected`);

  if (!isDeployConfigured()) {
    console.log(`${logPrefix}: skip — GCP not configured (run: npm run login)`);
    return;
  }

  console.log(`${logPrefix}: scheduling ${DEPLOY_TARGET} deploy…`);
  scheduleWebsiteDeploy();
  console.log(`${logPrefix}: done — track with npm run ci`);
}

main();
