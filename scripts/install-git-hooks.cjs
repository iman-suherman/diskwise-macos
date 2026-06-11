/**
 * Copy version-controlled hooks from githooks/ into .git/hooks/.
 */
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const sourceDir = path.join(root, "githooks");
const targetDir = path.join(root, ".git/hooks");

function main() {
  if (!fs.existsSync(targetDir)) {
    console.error("install-git-hooks: .git/hooks not found — is this a git repository?");
    process.exit(1);
  }
  if (!fs.existsSync(sourceDir)) {
    console.error("install-git-hooks: githooks/ directory not found");
    process.exit(1);
  }

  const hooks = fs.readdirSync(sourceDir).filter((name) => !name.startsWith("."));
  for (const name of hooks) {
    const source = path.join(sourceDir, name);
    if (!fs.statSync(source).isFile()) continue;
    const target = path.join(targetDir, name);
    fs.copyFileSync(source, target);
    fs.chmodSync(target, 0o755);
    console.log(`install-git-hooks: installed ${name}`);
  }
}

main();
