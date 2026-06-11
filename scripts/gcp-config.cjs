/**
 * Resolve GCP project ID from env or .env / .env.example
 */
const fs = require("fs");
const path = require("path");

const KEYS = ["GCP_PROJECT_ID", "GOOGLE_CLOUD_PROJECT"];
const USER_EMAIL_KEY = "GCP_USER_EMAIL";

function parseEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const out = {};
  for (const line of fs.readFileSync(filePath, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    const value = trimmed.slice(eq + 1).trim().replace(/^["']|["']$/g, "");
    if (value) out[key] = value;
  }
  return out;
}

function loadLocalEnv(repoRoot) {
  return parseEnvFile(path.join(repoRoot, ".env"));
}

function resolveGcpUserEmail(repoRoot) {
  return loadLocalEnv(repoRoot)[USER_EMAIL_KEY] || null;
}

function resolveLocalGcpProjectId(repoRoot) {
  const local = loadLocalEnv(repoRoot);
  for (const key of KEYS) {
    if (local[key]) return local[key];
  }
  return null;
}

function resolveGcpProjectId(repoRoot) {
  for (const key of KEYS) {
    if (process.env[key]) return process.env[key];
  }

  const dotEnv = parseEnvFile(path.join(repoRoot, ".env"));
  const example = parseEnvFile(path.join(repoRoot, ".env.example"));

  for (const key of KEYS) {
    if (dotEnv[key]) return dotEnv[key];
    if (example[key]) return example[key];
  }

  return null;
}

function upsertEnvKey(repoRoot, key, value) {
  const envPath = path.join(repoRoot, ".env");
  const line = `${key}=${value}`;

  if (!fs.existsSync(envPath)) {
    fs.writeFileSync(envPath, `${line}\n`, "utf8");
    console.log("login: wrote", envPath);
    return;
  }

  const content = fs.readFileSync(envPath, "utf8");
  const lines = content.split("\n");
  let found = false;

  const updated = lines.map((entry) => {
    const trimmed = entry.trim();
    if (!trimmed || trimmed.startsWith("#")) return entry;
    const eq = trimmed.indexOf("=");
    if (eq === -1) return entry;
    const entryKey = trimmed.slice(0, eq).trim();
    if (entryKey !== key) return entry;
    found = true;
    return line;
  });

  if (!found) {
    const suffix = updated.length && updated[updated.length - 1] !== "" ? "\n" : "";
    updated.push(line);
  }

  fs.writeFileSync(envPath, updated.join("\n").replace(/\n?$/, "\n"), "utf8");
  console.log("login: updated", envPath, `(${key}=${value})`);
}

module.exports = {
  parseEnvFile,
  loadLocalEnv,
  resolveGcpUserEmail,
  resolveLocalGcpProjectId,
  resolveGcpProjectId,
  upsertEnvKey,
};
