/**
 * Cloud Secret Manager (CSM) HTTP client.
 * https://secrets.mekari.io
 */
const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { assertCsmConfig, resolveCsmConfig, resolveCsmToken } = require("./csm-config.cjs");

function runCurl(args, { input = null } = {}) {
  const result = spawnSync("curl", args, {
    encoding: "utf8",
    input,
    stdio: ["pipe", "pipe", "pipe"],
    env: process.env,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const message = (result.stderr || result.stdout || "").trim();
    throw new Error(message || "curl request failed");
  }
  return (result.stdout || "").trim();
}

function repositoryBaseUrl(config) {
  return `${config.api.replace(/\/$/, "")}/repositories/${encodeURIComponent(config.repository)}`;
}

function csmRequest(config, token, method, urlPath, body = null) {
  const args = ["-sfS", "-X", method, "-H", `Authorization: Bearer ${token}`];
  if (body !== null) {
    args.push("-H", "Content-Type: application/json", "--data-binary", "@-");
  }
  args.push(`${repositoryBaseUrl(config)}${urlPath}`);
  const payload = body === null ? null : `${JSON.stringify(body)}\n`;
  return runCurl(args, { input: payload });
}

function fetchEnvMap(config, token) {
  const query = new URLSearchParams({
    clientId: config.clientId,
    environment: config.environment,
  });
  const raw = csmRequest(config, token, "GET", `/env?${query.toString()}`);
  const parsed = JSON.parse(raw);
  if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
    return parsed;
  }
  throw new Error("CSM /env returned unexpected payload");
}

function fetchDotenv(config, token) {
  const query = new URLSearchParams({
    clientId: config.clientId,
    environment: config.environment,
    format: "dotenv",
  });
  return csmRequest(config, token, "GET", `/env?${query.toString()}`);
}

function fetchSecret(config, token, key) {
  const query = new URLSearchParams({
    clientId: config.clientId,
    environment: config.environment,
  });
  const raw = csmRequest(
    config,
    token,
    "GET",
    `/secrets/${encodeURIComponent(key)}?${query.toString()}`,
  );
  const parsed = JSON.parse(raw);
  if (typeof parsed === "string") return parsed;
  if (parsed && typeof parsed.value === "string") return parsed.value;
  throw new Error(`CSM secret ${key} returned unexpected payload`);
}

function setSecret(config, token, name, value) {
  const query = new URLSearchParams({ clientId: config.clientId });
  csmRequest(config, token, "PUT", `/secrets?${query.toString()}`, {
    name,
    value,
    environment: config.environment,
  });
}

function bulkSetSecrets(config, token, entries) {
  const query = new URLSearchParams({ clientId: config.clientId });
  const variables = {};
  for (const { name, value } of entries) {
    variables[name] = value;
  }
  csmRequest(config, token, "PUT", `/secrets/bulk?${query.toString()}`, {
    environment: config.environment,
    variables,
  });
}

function csmAvailable() {
  const result = spawnSync("curl", ["--version"], { encoding: "utf8", stdio: "pipe" });
  return !result.error && result.status === 0;
}

function loadCsmContext(repoRoot, { requireToken = true } = {}) {
  const config = resolveCsmConfig(repoRoot);
  assertCsmConfig(config);
  const token = resolveCsmToken();
  if (requireToken && !token) {
    throw new Error(
      "CSM auth token not found — run: tick login (or set CSM_TOKEN)",
    );
  }
  return { config, token };
}

function expandHome(value) {
  if (!value) return value;
  return value.startsWith("~/") ? path.join(process.env.HOME || os.homedir(), value.slice(2)) : value;
}

function resolveIdentityPath(repoRoot, identityValue) {
  const raw = identityValue || ".ssh/suherman-tailscale-ed25519";
  const expanded = expandHome(raw);
  if (path.isAbsolute(expanded)) return expanded;
  return path.join(repoRoot, expanded);
}

function materializeIdentity(repoRoot, { path: identityPath, privateKey, publicKey }, { quiet = false } = {}) {
  if (!privateKey || !publicKey) {
    throw new Error("tailscale identity missing privateKey or publicKey");
  }

  const resolvedPath = resolveIdentityPath(repoRoot, identityPath);
  const publicPath = `${resolvedPath}.pub`;
  fs.mkdirSync(path.dirname(resolvedPath), { recursive: true });
  fs.writeFileSync(resolvedPath, privateKey.endsWith("\n") ? privateKey : `${privateKey}\n`, {
    mode: 0o600,
  });
  fs.writeFileSync(
    publicPath,
    publicKey.endsWith("\n") ? publicKey : `${publicKey}\n`,
    { mode: 0o644 },
  );

  if (!quiet) {
    console.log("generate-env: wrote SSH identity", resolvedPath);
  }

  return {
    identityPath: resolvedPath,
    publicPath,
    publicKey: publicKey.trim(),
    identityEnv: path.relative(repoRoot, resolvedPath) || ".ssh/suherman-tailscale-ed25519",
  };
}

function tailscaleEnvFromKeys(envMap) {
  const out = {
    TAILSCALE_SSH_IDENTITY: envMap.TAILSCALE_SSH_IDENTITY || ".ssh/suherman-tailscale-ed25519",
    TAILSCALE_SSH_PUBLIC_KEY: (envMap.TAILSCALE_SSH_PUBLIC_KEY || "").trim(),
  };

  for (const prefix of ["TAILSCALE_SSH_MBP1", "TAILSCALE_SSH_MBP16"]) {
    for (const suffix of ["HOST", "IP", "USER", "ALIAS"]) {
      const key = `${prefix}_${suffix}`;
      if (envMap[key]) out[key] = envMap[key];
    }
  }

  return out;
}

function hydrateTailscaleIdentity(repoRoot, envMap, { quiet = false } = {}) {
  const privateKey = envMap.TAILSCALE_SSH_PRIVATE_KEY;
  const publicKey = envMap.TAILSCALE_SSH_PUBLIC_KEY;
  if (!privateKey || !publicKey) return null;

  const materialized = materializeIdentity(
    repoRoot,
    {
      path: envMap.TAILSCALE_SSH_IDENTITY || ".ssh/suherman-tailscale-ed25519",
      privateKey,
      publicKey,
    },
    { quiet },
  );

  return {
    ...tailscaleEnvFromKeys({
      ...envMap,
      TAILSCALE_SSH_PUBLIC_KEY: materialized.publicKey,
      TAILSCALE_SSH_IDENTITY: materialized.identityEnv,
    }),
  };
}

/** Env keys hydrated from CSM for suherman-net-infra. */
const MANAGED_ENV_KEYS = [
  "CLOUDFLARE_API_TOKEN",
  "CLOUDFLARE_ACCOUNT_ID",
  "CLOUDFLARE_TUNNEL_TOKEN",
  "CLOUDFLARE_TUNNEL_TOKEN_VIDEO",
  "CLOUDFLARE_TUNNEL_TOKEN_CT_MCP",
  "OLLAMA_AI_ADMIN_TOKEN",
  "GA_DISKWISE_API_SECRET",
  "GA_NUCLEUS_API_SECRET",
  "GA_CT_MCP_API_SECRET",
  "TAILSCALE_SSH_PRIVATE_KEY",
  "TAILSCALE_SSH_PUBLIC_KEY",
  "TAILSCALE_SSH_IDENTITY",
  "TAILSCALE_SSH_MBP1_HOST",
  "TAILSCALE_SSH_MBP1_IP",
  "TAILSCALE_SSH_MBP1_USER",
  "TAILSCALE_SSH_MBP1_ALIAS",
  "TAILSCALE_SSH_MBP16_HOST",
  "TAILSCALE_SSH_MBP16_IP",
  "TAILSCALE_SSH_MBP16_USER",
  "TAILSCALE_SSH_MBP16_ALIAS",
];

/** GCP service account JSON files materialized by generate-env. */
const MANAGED_FILE_SECRETS = [
  {
    secretId: "GCS_SA_KEY_JSON",
    outputPath: "service-account-key.json",
    encoding: "utf8",
  },
  {
    secretId: "GCS_SA_KEY_CT_MCP_JSON",
    outputPath: "service-account-key-ct-mcp.json",
    encoding: "utf8",
  },
];

function pickManagedEnvEntries(envMap) {
  const entries = {};
  for (const key of MANAGED_ENV_KEYS) {
    if (envMap[key]) entries[key] = envMap[key];
  }
  return entries;
}

function materializeFileSecrets(repoRoot, envMap, { quiet = false } = {}) {
  const written = [];
  for (const { secretId, outputPath, encoding = "utf8" } of MANAGED_FILE_SECRETS) {
    const value = envMap[secretId];
    if (!value) continue;

    const filePath = path.join(repoRoot, outputPath);
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    const payload =
      encoding === "base64" ? Buffer.from(value, "base64") : Buffer.from(value, "utf8");
    fs.writeFileSync(filePath, payload, { mode: 0o600 });
    written.push(outputPath);
    if (!quiet) {
      console.log("generate-env: wrote", outputPath, "from CSM", secretId);
    }
  }
  return written;
}

function hydrateManagedSecrets(repoRoot, { quiet = false } = {}) {
  if (!csmAvailable()) {
    throw new Error("curl not found — install curl to pull CSM secrets");
  }

  const { config, token } = loadCsmContext(repoRoot);
  if (!quiet) {
    console.log(
      `generate-env: pulling CSM secrets for ${config.repository} (${config.environment})`,
    );
  }

  const envMap = fetchEnvMap(config, token);
  const entries = pickManagedEnvEntries(envMap);
  const tailscale = hydrateTailscaleIdentity(repoRoot, envMap, { quiet });
  if (tailscale) {
    Object.assign(entries, tailscale);
    delete entries.TAILSCALE_SSH_PRIVATE_KEY;
  }

  const gcsKeys = materializeFileSecrets(repoRoot, envMap, { quiet });

  return {
    config,
    entries,
    hydrated: {
      cloudflare: Boolean(entries.CLOUDFLARE_API_TOKEN && entries.CLOUDFLARE_ACCOUNT_ID),
      tailscale: Boolean(tailscale?.TAILSCALE_SSH_PUBLIC_KEY),
      gaDiskwise: Boolean(entries.GA_DISKWISE_API_SECRET),
      gaNucleus: Boolean(entries.GA_NUCLEUS_API_SECRET),
      gaCtMcp: Boolean(entries.GA_CT_MCP_API_SECRET),
      gcsKeys: gcsKeys.length > 0,
    },
  };
}

module.exports = {
  MANAGED_ENV_KEYS,
  MANAGED_FILE_SECRETS,
  bulkSetSecrets,
  csmAvailable,
  fetchDotenv,
  fetchEnvMap,
  fetchSecret,
  hydrateManagedSecrets,
  hydrateTailscaleIdentity,
  loadCsmContext,
  materializeFileSecrets,
  materializeIdentity,
  pickManagedEnvEntries,
  setSecret,
  tailscaleEnvFromKeys,
};
