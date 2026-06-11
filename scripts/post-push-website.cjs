/**
 * Background worker invoked after git push.
 * Deploys diskwise.suherman.net when pushed commits touch website/.
 */
const {
  commitTouchesWebsite,
  getCommitFiles,
  getCommitFilesInRange,
  isDeployConfigured,
  scheduleWebsiteDeploy,
  waitForPushTarget,
  DEPLOY_TARGET,
} = require("./website-deploy-worker.cjs");

const logPrefix = "post-push-website";

async function main() {
  if (process.env.DISKWise_POST_PUSH_WEBSITE === "0") {
    console.log(`${logPrefix}: disabled (DISKWise_POST_PUSH_WEBSITE=0)`);
    return;
  }

  const pushRange = process.env.DISKWise_PUSH_RANGE?.trim() || process.argv[2]?.trim();
  const pushTarget = process.env.DISKWise_PUSH_TARGET?.trim();
  const remoteRef = process.env.DISKWise_PUSH_REMOTE_REF?.trim() || "@{u}";

  if (process.env.DISKWise_WAIT_FOR_PUSH === "1" && pushTarget) {
    console.log(`${logPrefix}: waiting for push to ${remoteRef} (${pushTarget.slice(0, 7)})…`);
    const landed = await waitForPushTarget(pushTarget, remoteRef);
    if (!landed) {
      console.log(`${logPrefix}: skip — push did not land on ${remoteRef} within timeout`);
      return;
    }
  }

  const files = pushRange
    ? getCommitFilesInRange(pushRange)
    : getCommitFiles("HEAD");

  if (!commitTouchesWebsite(files)) {
    console.log(`${logPrefix}: skip — no website/ changes in pushed commits`);
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

main().catch((err) => {
  console.error(`${logPrefix}: error`, err);
  process.exit(1);
});
