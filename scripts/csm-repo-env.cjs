/**
 * Shared CSM generate-env + seed helpers for stack repos.
 */
const fs = require("fs");
const path = require("path");
const {
  bulkSetSecrets,
  csmAvailable,
  fetchSecret,
  loadCsmContext,
  setSecret,
} = require("./csm-secrets-lib.cjs");

function resolveExamplePath(repoRoot) {
  for (const name of [".env.example", ".env-example"]) {
    const filePath = path.join(repoRoot, name);
    if (fs.existsSync(filePath)) return filePath;
  }
  return null;
}

function orderedKeys(exampleContent, existingKeys, secretKeys) {
  const keys = [];
  const seen = new Set();

  for (const line of exampleContent.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    if (!seen.has(key)) {
      seen.add(key);
      keys.push(key);
    }
  }

  for (const key of existingKeys) {
    if (!seen.has(key)) {
      seen.add(key);
      keys.push(key);
    }
  }

  for (const key of secretKeys) {
    if (!seen.has(key)) {
      seen.add(key);
      keys.push(key);
    }
  }

  return keys;
}

function formatEnv(keys, values) {
  const lines = [];
  for (const key of keys) {
    const value = values[key];
    if (value === undefined || value === "" || value === "undefined") continue;
    lines.push(`${key}=${value}`);
  }
  return `${lines.join("\n")}\n`;
}

function createCsmSecrets(repoRoot, { managedSecrets, managedFileSecrets = [] }) {
  function loadContext(options = {}) {
    return loadCsmContext(repoRoot, options);
  }

  function secretExists(secretId, options = {}) {
    try {
      const { config, token } = loadContext(options);
      fetchSecret(config, token, secretId);
      return true;
    } catch {
      return false;
    }
  }

  function accessSecret(secretId, options = {}) {
    const { config, token } = loadContext(options);
    return fetchSecret(config, token, secretId);
  }

  function addSecretVersion(secretId, value, options = {}) {
    const { config, token } = loadContext(options);
    setSecret(config, token, secretId, value);
  }

  function addSecretVersionFromFile(secretId, filePath, { encoding = "binary" } = {}, options = {}) {
    const value = fs.readFileSync(filePath);
    const payload = encoding === "base64" ? value.toString("base64") : value.toString("utf8");
    addSecretVersion(secretId, payload, options);
  }

  function materializeManagedFileSecrets(existing, merged, { accessSecretFn = accessSecret, quiet = false } = {}) {
    for (const { secretId, envKey, outputPath, encoding = "binary" } of managedFileSecrets) {
      const absoluteOutputPath = path.join(repoRoot, outputPath);
      try {
        const raw = accessSecretFn(secretId);
        const contents =
          encoding === "base64" ? Buffer.from(raw.trim(), "base64") : Buffer.from(raw, "binary");
        fs.mkdirSync(path.dirname(absoluteOutputPath), { recursive: true });
        fs.writeFileSync(absoluteOutputPath, contents);
        merged[envKey] = outputPath;
        if (!quiet) {
          console.log(`generate-env: wrote ${outputPath} from CSM (${secretId})`);
        }
      } catch (error) {
        if (fs.existsSync(absoluteOutputPath)) {
          merged[envKey] = existing[envKey] || outputPath;
          if (!quiet) {
            console.log(`generate-env: kept local ${outputPath} (CSM unavailable)`);
          }
          continue;
        }
        if (!quiet) {
          console.log(`generate-env: skip ${secretId} (${error.message})`);
        }
      }
    }
  }

  function generateEnv({
    parseEnvFile,
    applyGcpEnv,
    resolveGcpProjectId,
    resolveAdcPath,
    force = false,
    quiet = false,
  }) {
    const examplePath = resolveExamplePath(repoRoot);
    const envPath = path.join(repoRoot, ".env");

    if (!examplePath) {
      throw new Error("missing .env.example or .env-example");
    }

    if (applyGcpEnv) applyGcpEnv(repoRoot);

    const exampleContent = fs.readFileSync(examplePath, "utf8");
    const example = parseEnvFile(examplePath);
    const existing = parseEnvFile(envPath);

    if (force || !fs.existsSync(envPath)) {
      fs.copyFileSync(examplePath, envPath);
      if (!quiet) {
        console.log("generate-env: wrote", envPath, "from", path.basename(examplePath));
      }
    } else if (!quiet) {
      console.log("generate-env: refreshing secrets in existing .env");
    }

    if (resolveGcpProjectId) {
      const projectId = resolveGcpProjectId(repoRoot);
      if (!projectId) {
        throw new Error("GCP_PROJECT_ID is not set. Add it to .env or run npm run login.");
      }
    }

    const secrets = {};
    if (csmAvailable()) {
      try {
        const { config, token } = loadContext();
        if (!quiet) {
          console.log(
            `generate-env: pulling CSM secrets for ${config.repository} (${config.environment})`,
          );
        }
        for (const key of managedSecrets) {
          try {
            secrets[key] = fetchSecret(config, token, key);
            if (!quiet) console.log(`generate-env: loaded ${key} from CSM`);
          } catch (error) {
            if (existing[key] && existing[key] !== "undefined") {
              secrets[key] = existing[key];
              if (!quiet) console.log(`generate-env: kept local ${key} (CSM unavailable)`);
            } else if (!quiet) {
              console.log(`generate-env: skip ${key} (${error.message})`);
            }
          }
        }
      } catch (error) {
        if (!quiet) console.log(`generate-env: CSM unavailable (${error.message})`);
      }
    } else if (!quiet) {
      console.log("generate-env: curl not found — skipping CSM pull");
    }

    const merged = { ...example, ...existing, ...secrets };
    materializeManagedFileSecrets(existing, merged, { quiet });

    if (resolveAdcPath) {
      const adcPath = resolveAdcPath(repoRoot, { sync: true });
      if (adcPath) {
        merged.GOOGLE_APPLICATION_CREDENTIALS = adcPath;
      } else {
        delete merged.GOOGLE_APPLICATION_CREDENTIALS;
        if (!quiet) {
          console.log("generate-env: no ADC file — run npm run login");
        }
      }
    }

    const keys = orderedKeys(exampleContent, Object.keys(existing), managedSecrets);
    fs.writeFileSync(envPath, formatEnv(keys, merged), "utf8");
    if (!quiet) console.log(`generate-env: wrote ${envPath}`);
    return { path: envPath, secretsLoaded: Object.keys(secrets).length };
  }

  function seedSecrets({ loadDotenv, applyGcpEnv, allowEmpty = false } = {}) {
    if (applyGcpEnv) applyGcpEnv(repoRoot);
    const env = loadDotenv ? loadDotenv(repoRoot) : parseEnvFile(path.join(repoRoot, ".env"));

    let seeded = 0;
    const entries = [];

    for (const key of managedSecrets) {
      const value = env[key]?.trim();
      if (!value) {
        console.log(`seed-secrets: skip ${key} (not set in .env)`);
        continue;
      }
      entries.push({ name: key, value });
      seeded += 1;
      console.log(`seed-secrets: queued ${key}`);
    }

    for (const { secretId, envKey, outputPath, encoding } of managedFileSecrets) {
      const configuredPath = env[envKey]?.trim();
      const filePath = configuredPath
        ? path.isAbsolute(configuredPath)
          ? configuredPath
          : path.join(repoRoot, configuredPath)
        : path.join(repoRoot, outputPath);

      if (!fs.existsSync(filePath)) {
        console.log(`seed-secrets: skip ${secretId} (missing file ${filePath})`);
        continue;
      }

      const value = fs.readFileSync(filePath);
      const payload = (encoding ?? "binary") === "base64" ? value.toString("base64") : value.toString("utf8");
      entries.push({ name: secretId, value: payload });
      seeded += 1;
      console.log(`seed-secrets: queued ${secretId} from ${filePath}`);
    }

    if (!seeded && !allowEmpty) {
      throw new Error("no managed secrets found in .env");
    }

    if (entries.length > 0) {
      const { config, token } = loadContext();
      bulkSetSecrets(config, token, entries);
      for (const { name } of entries) {
        console.log(`seed-secrets: updated ${name} in CSM`);
      }
    }

    return seeded;
  }

  return {
    MANAGED_SECRETS: managedSecrets,
    MANAGED_FILE_SECRETS: managedFileSecrets,
    accessSecret,
    addSecretVersion,
    addSecretVersionFromFile,
    generateEnv,
    materializeManagedFileSecrets,
    secretExists,
    seedSecrets,
  };
}

module.exports = { createCsmSecrets, resolveExamplePath };
