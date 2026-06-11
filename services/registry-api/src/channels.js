const DEFAULT_CHANNEL = "stable";

function normalizeChannel(value) {
  const channel = String(value || DEFAULT_CHANNEL)
    .trim()
    .toLowerCase();
  if (channel === "insiders" || channel === "beta" || channel === "preview") {
    return "insiders";
  }
  return DEFAULT_CHANNEL;
}

function isPrereleaseVersion(version) {
  if (!version) return false;
  if (version.semver?.prerelease) return true;
  return /-\w/.test(String(version.version || ""));
}

function matchesChannel(version, channel) {
  const normalized = normalizeChannel(channel);
  if (normalized === "insiders") {
    return version.channel === "insiders" || isPrereleaseVersion(version);
  }
  if (version.channel === "insiders") return false;
  return !isPrereleaseVersion(version);
}

function pickLatestForChannel(versions, channel) {
  const normalized = normalizeChannel(channel);
  const filtered = versions.filter((version) => matchesChannel(version, normalized));
  if (filtered.length > 0) return filtered[0];
  if (normalized === "insiders") return versions[0] || null;
  return versions.find((version) => !isPrereleaseVersion(version)) || versions[0] || null;
}

module.exports = {
  DEFAULT_CHANNEL,
  normalizeChannel,
  isPrereleaseVersion,
  matchesChannel,
  pickLatestForChannel,
};
