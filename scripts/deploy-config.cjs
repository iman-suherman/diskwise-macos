/**
 * Local auto-deploy targets for DiskWise (website, registry, download, app, iOS).
 */
const path = require("node:path");

const REPO_ROOT = path.resolve(__dirname, "..");
const DEFAULT_BRANCH = process.env.DISKWise_DEPLOY_BRANCH || "main";

/** @type {Array<{
 *   repo: string;
 *   label: string;
 *   url?: string;
 *   branch?: string;
 *   npmScript?: string;
 *   note?: string;
 *   details?: string[];
 *   infraDeploy?: boolean;
 *   syncOnly?: boolean;
 *   gcpServiceWeights?: Record<string, number>;
 * }>} */
const DEPLOY_TARGETS = [
  {
    repo: "diskwise-website",
    label: "diskwise.suherman.net",
    url: "https://diskwise.suherman.net",
    branch: DEFAULT_BRANCH,
    npmScript: "deploy:website",
    gcpServiceWeights: { "Cloud Run": 1 },
    details: [
      "GHCR via suherman-net-infra helper: ghcr.io/iman-suherman/diskwise-website:<sha>",
      "Deploy: npm run deploy:website (build+push+Cloud Run)",
    ],
  },
  {
    repo: "diskwise-download",
    label: "diskwise-download.suherman.net",
    url: "https://diskwise-download.suherman.net",
    infraDeploy: true,
    syncOnly: true,
    note: "Cloudflare Worker",
    gcpServiceWeights: { "Cloud Storage": 1 },
    details: [
      "Deploy from suherman-net-infra: npm run cloudflare:diskwise -- --skip-website --skip-registry",
      "Checkpoint sync: npm run deploy:sync (no worker changes in this repo)",
    ],
  },
  {
    repo: "diskwise-registry",
    label: "diskwise-registry.suherman.net",
    url: "https://diskwise-registry.suherman.net",
    branch: DEFAULT_BRANCH,
    npmScript: "deploy:registry",
    gcpServiceWeights: { "Cloud Run": 1, "App Engine": 1 },
    details: [
      "GHCR via suherman-net-infra helper: ghcr.io/iman-suherman/diskwise-registry-api:<sha>",
      "Deploy: npm run deploy:registry (build+push+Cloud Run)",
    ],
  },
  {
    repo: "diskwise-app",
    label: "DiskWise macOS DMG",
    url: "https://diskwise-download.suherman.net/downloads",
    branch: DEFAULT_BRANCH,
    npmScript: "release:direct",
    gcpServiceWeights: { "Artifact Registry": 1 },
    details: [
      "Manual: npm run release",
      "Retry: npm run deploy:retry -- --repo diskwise-app",
    ],
  },
  {
    repo: "diskwise-ios",
    label: "DiskWise iOS (App Store)",
    url: "https://apps.apple.com/app/id6806657352",
    branch: DEFAULT_BRANCH,
    npmScript: "publish:testflight",
    syncOnly: true,
    note: "TestFlight / ASC",
    details: [
      "Publish: npm run publish:testflight",
      "Listing / review: npm run appstore:upload / appstore:submit",
      "Checkpoint sync: npm run deploy:sync (does not upload builds)",
    ],
  },
];

function getDeployTarget(repo) {
  return DEPLOY_TARGETS.find((t) => t.repo === repo) || null;
}

function deployableTargets() {
  return DEPLOY_TARGETS.filter((t) => t.npmScript && !t.syncOnly);
}

function syncableTargets() {
  return DEPLOY_TARGETS.filter((t) => t.npmScript || t.syncOnly || t.infraDeploy);
}

module.exports = {
  REPO_ROOT,
  DEFAULT_BRANCH,
  DEPLOY_TARGETS,
  getDeployTarget,
  deployableTargets,
  syncableTargets,
};
