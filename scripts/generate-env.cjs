/**
 * Copy .env.example to .env (cross-platform).
 * Use --force to overwrite an existing .env
 */
const fs = require("fs");
const path = require("path");

/**
 * @param {string} repoRoot
 * @param {{ force?: boolean, quiet?: boolean }} [options]
 * @returns {{ created: boolean, skipped: boolean, path: string }}
 */
function generateEnv(repoRoot, { force = false, quiet = false } = {}) {
  const examplePath = path.join(repoRoot, ".env.example");
  const envPath = path.join(repoRoot, ".env");

  if (!fs.existsSync(examplePath)) {
    console.error("generate-env: .env.example not found at", examplePath);
    process.exit(1);
  }

  if (fs.existsSync(envPath) && !force) {
    if (!quiet) {
      console.error(
        "generate-env: .env already exists. Remove it first, or run:\n" +
          "  npm run generate-env -- --force"
      );
      process.exit(1);
    }
    return { created: false, skipped: true, path: envPath };
  }

  fs.copyFileSync(examplePath, envPath);
  if (!quiet) {
    console.log("generate-env: wrote", envPath, "from .env.example");
  }
  return { created: true, skipped: false, path: envPath };
}

if (require.main === module) {
  const root = path.join(__dirname, "..");
  const force = process.argv.includes("--force");
  generateEnv(root, { force });
}

module.exports = { generateEnv };
