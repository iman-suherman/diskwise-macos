/**
 * Local auto-deploy targets for diskwise.suherman.net.
 */
const path = require("node:path");

const REPO_ROOT = path.resolve(__dirname, "..");
const DEFAULT_BRANCH = process.env.DISKWise_DEPLOY_BRANCH || "main";

/** @type {Array<{ repo: string; label: string; branch?: string; npmScript?: string; note?: string; details?: string[] }>} */
const DEPLOY_TARGETS = [
  {
    repo: "diskwise-website",
    label: "diskwise.suherman.net",
    branch: DEFAULT_BRANCH,
    npmScript: "deploy:website",
  },
  {
    repo: "diskwise-download",
    label: "diskwise-download.suherman.net",
    infraDeploy: true,
    note: "manual",
    details: ["Deploy from suherman-net-infra: npm run cloudflare:diskwise -- --skip-website --skip-registry"],
  },
  {
    repo: "diskwise-registry",
    label: "diskwise-registry.suherman.net",
    branch: DEFAULT_BRANCH,
    npmScript: "deploy:registry",
  },
  {
    repo: "diskwise-app",
    label: "DiskWise macOS DMG",
    branch: DEFAULT_BRANCH,
    npmScript: "release:direct",
    details: [
      "Manual: npm run release",
      "Retry: npm run diskwise:deploy:retry -- --repo diskwise-app",
    ],
  },
];

function getDeployTarget(repo) {
  return DEPLOY_TARGETS.find((t) => t.repo === repo) || null;
}

function deployableTargets() {
  return DEPLOY_TARGETS.filter((t) => t.npmScript);
}

module.exports = {
  REPO_ROOT,
  DEFAULT_BRANCH,
  DEPLOY_TARGETS,
  getDeployTarget,
  deployableTargets,
};
