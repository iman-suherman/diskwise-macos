/**
 * Cloud Secret Manager (CSM) — repo link + auth resolution.
 * https://secrets.mekari.io
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");
const { parseEnvFile } = require("./gcp-config.cjs");

const DEFAULT_CSM_API = "https://secrets.mekari.io/api";

/** Production UI is at secrets.mekari.io; API routes are under /api/. */
function normalizeCsmApi(url) {
  const trimmed = String(url || "").replace(/\/$/, "");
  if (!trimmed) return DEFAULT_CSM_API;
  if (trimmed.endsWith("/api")) return trimmed;
  try {
    const { hostname } = new URL(trimmed);
    if (hostname === "secrets.mekari.io" || hostname.endsWith(".secrets.mekari.io")) {
      return `${trimmed}/api`;
    }
  } catch {
    // ignore invalid URL
  }
  return trimmed;
}
const DEFAULT_ENVIRONMENT = "development";

function readJsonFile(filePath) {
  if (!fs.existsSync(filePath)) return null;
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function detectGitRepoSlug(repoRoot) {
  const result = spawnSync("git", ["remote", "get-url", "origin"], {
    cwd: repoRoot,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.status !== 0) return null;
  const remote = (result.stdout || "").trim();
  const match = remote.match(/[:/]([^/]+)\/([^/.]+?)(?:\.git)?$/);
  return match ? match[2] : null;
}

function readEnvSources(repoRoot) {
  const sources = [];
  for (const name of [".env", ".env-example", ".env.example"]) {
    const filePath = path.join(repoRoot, name);
    if (fs.existsSync(filePath)) {
      sources.push(parseEnvFile(filePath));
    }
  }
  return sources;
}

function pickEnvValue(sources, key) {
  for (const source of sources) {
    const value = source[key];
    if (value && value.trim()) return value.trim();
  }
  return null;
}

function resolveCsmConfig(repoRoot) {
  const tickproject = readJsonFile(path.join(repoRoot, ".tickproject"));
  const envSources = readEnvSources(repoRoot);

  const api = normalizeCsmApi(
    process.env.CSM_API?.trim() ||
      pickEnvValue(envSources, "CSM_API") ||
      DEFAULT_CSM_API
  );

  const clientId =
    process.env.CSM_CLIENT_ID?.trim() ||
    pickEnvValue(envSources, "CSM_CLIENT_ID") ||
    tickproject?.clientId?.trim() ||
    null;

  const repository =
    process.env.CSM_REPOSITORY?.trim() ||
    pickEnvValue(envSources, "CSM_REPOSITORY") ||
    tickproject?.repository?.trim() ||
    detectGitRepoSlug(repoRoot);

  const environment =
    process.env.CSM_ENVIRONMENT?.trim() ||
    pickEnvValue(envSources, "CSM_ENVIRONMENT") ||
    tickproject?.environment?.trim() ||
    DEFAULT_ENVIRONMENT;

  return { api, clientId, repository, environment };
}

function readTokenFile(filePath) {
  if (!fs.existsSync(filePath)) return null;
  const raw = fs.readFileSync(filePath, "utf8").trim();
  if (!raw) return null;
  if (raw.startsWith("{")) {
    const parsed = JSON.parse(raw);
    return parsed.token || parsed.accessToken || parsed.access_token || null;
  }
  return raw;
}

function resolveTickConfigModule() {
  const candidates = [
    process.env.TICK_PACKAGE_ROOT,
    path.join(process.env.HOME || os.homedir(), "src/tiktopus/cloud-secret-manager"),
    path.join(process.env.HOME || os.homedir(), "src/personal/cloud-secret-manager"),
  ].filter(Boolean);

  for (const root of candidates) {
    const modulePath = path.join(root, "packages/tick/dist/lib/config.js");
    if (fs.existsSync(modulePath)) return modulePath;
  }

  const which = spawnSync("which", ["tick"], { encoding: "utf8" });
  if (which.status === 0 && which.stdout?.trim()) {
    try {
      const tickBin = fs.realpathSync(which.stdout.trim());
      const modulePath = path.resolve(path.dirname(tickBin), "../lib/node_modules/@ticktopus/tick/dist/lib/config.js");
      if (fs.existsSync(modulePath)) return modulePath;
    } catch {
      // ignore
    }
  }

  return null;
}

function resolveCsmTokenFromTickKeychain() {
  const modulePath = resolveTickConfigModule();
  if (!modulePath) return null;

  const script = `
    import { pathToFileURL } from "node:url";
    const { loadCredentials } = await import(pathToFileURL(${JSON.stringify(modulePath)}).href);
    const creds = await loadCredentials();
    if (creds?.token) process.stdout.write(creds.token);
  `;

  const result = spawnSync(process.execPath, ["--input-type=module", "-e", script], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.status === 0 && result.stdout?.trim()) {
    return result.stdout.trim();
  }
  return null;
}

function resolveCsmToken() {
  if (process.env.CSM_TOKEN?.trim()) {
    return process.env.CSM_TOKEN.trim();
  }

  for (const command of [
    ["tick", ["auth", "print-token"]],
    ["tick", ["token"]],
  ]) {
    const result = spawnSync(command[0], command[1], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    if (result.status === 0 && result.stdout?.trim()) {
      return result.stdout.trim();
    }
  }

  const keychainToken = resolveCsmTokenFromTickKeychain();
  if (keychainToken) return keychainToken;

  const home = process.env.HOME || os.homedir();
  for (const tokenPath of [
    path.join(home, ".tick", "token"),
    path.join(home, ".config", "tick", "token"),
    path.join(home, ".config", "tick", "credentials.json"),
    path.join(home, ".cloud-secret-manager", "token"),
  ]) {
    try {
      const token = readTokenFile(tokenPath);
      if (token) return token;
    } catch {
      // try next path
    }
  }

  return null;
}

function assertCsmConfig(config) {
  const problems = [];
  if (!config.clientId) {
    problems.push("CSM_CLIENT_ID is not set (add to .env or .tickproject)");
  }
  if (!config.repository) {
    problems.push("CSM_REPOSITORY is not set and git origin could not be detected");
  }
  if (problems.length > 0) {
    const err = new Error(problems.join("; "));
    err.problems = problems;
    throw err;
  }
}

module.exports = {
  DEFAULT_CSM_API,
  DEFAULT_ENVIRONMENT,
  detectGitRepoSlug,
  normalizeCsmApi,
  resolveCsmConfig,
  resolveCsmToken,
  assertCsmConfig,
};
