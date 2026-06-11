const SEMVER_PATTERN =
  /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/;

function parseSemver(version) {
  const match = String(version).trim().match(SEMVER_PATTERN);
  if (!match) return null;

  return {
    version: String(version).trim(),
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
    prerelease: match[4] || null,
    build: match[5] || null,
  };
}

function assertSemver(version, label = "version") {
  const parsed = parseSemver(version);
  if (!parsed) {
    throw new Error(`${label} "${version}" is not valid semantic versioning (MAJOR.MINOR.PATCH)`);
  }
  if (parsed.prerelease) {
    throw new Error(`${label} "${version}" must be a stable release (no prerelease suffix)`);
  }
  return parsed;
}

function versionSortKey(parsed) {
  return parsed.major * 1_000_000 + parsed.minor * 1_000 + parsed.patch;
}

function compareSemver(a, b) {
  const left = typeof a === "string" ? parseSemver(a) : a;
  const right = typeof b === "string" ? parseSemver(b) : b;
  if (!left || !right) return 0;
  return versionSortKey(left) - versionSortKey(right);
}

function versionDocId(pluginId, version) {
  return `${pluginId}__${version}`;
}

function formatSemver(parsed) {
  return `${parsed.major}.${parsed.minor}.${parsed.patch}`;
}

function bumpSemver(currentVersion, bump) {
  const parsed = assertSemver(currentVersion, "version");
  if (bump === "major") {
    return formatSemver({ major: parsed.major + 1, minor: 0, patch: 0 });
  }
  if (bump === "minor") {
    return formatSemver({ major: parsed.major, minor: parsed.minor + 1, patch: 0 });
  }
  return formatSemver({
    major: parsed.major,
    minor: parsed.minor,
    patch: parsed.patch + 1,
  });
}

module.exports = {
  SEMVER_PATTERN,
  parseSemver,
  assertSemver,
  versionSortKey,
  compareSemver,
  versionDocId,
  bumpSemver,
  formatSemver,
};
