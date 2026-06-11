const DEFAULT_REGISTRY_API_BASE = "https://diskwise-registry.suherman.net";

function resolveRegistryApiBase() {
  return (
    process.env.REGISTRY_API_PUBLIC_URL?.trim() ||
    process.env.NEXT_PUBLIC_REGISTRY_API_URL?.trim() ||
    DEFAULT_REGISTRY_API_BASE
  ).replace(/\/$/, "");
}

function publicAppcastUrl(pluginId) {
  const id = pluginId || process.env.DEFAULT_APP_ID?.trim() || "diskwise-macos";
  return `${resolveRegistryApiBase()}/api/v1/plugins/${id}/appcast.xml`;
}

function withPublicAppcastUrl(record) {
  if (!record || typeof record !== "object") return record;
  return {
    ...record,
    publicAppcastUrl: publicAppcastUrl(record.pluginId),
  };
}

module.exports = {
  publicAppcastUrl,
  withPublicAppcastUrl,
  resolveRegistryApiBase,
};
