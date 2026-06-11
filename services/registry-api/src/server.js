const express = require("express");
const {
  listPlugins,
  listPluginVersions,
  getPluginVersion,
  getLatestPluginVersion,
} = require("./firestore");
const { normalizeChannel } = require("./channels");
const { withPublicDownloadUrls } = require("./download-urls");
const { fetchAppcastXml } = require("./appcast");

const DEFAULT_PLUGIN_ID =
  process.env.DEFAULT_APP_ID?.trim() || "diskwise-macos";

const app = express();
const port = Number(process.env.PORT || 8080);

app.use(express.json());
app.use((_req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", process.env.CORS_ORIGIN || "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  if (_req.method === "OPTIONS") {
    res.status(204).end();
    return;
  }
  next();
});

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

async function serveAppcast(req, res, next) {
  try {
    const pluginId = req.params.pluginId || DEFAULT_PLUGIN_ID;
    const xml = await fetchAppcastXml(pluginId);
    res.setHeader("Content-Type", "application/xml; charset=utf-8");
    res.setHeader("Cache-Control", "public, max-age=300");
    res.send(xml);
  } catch (err) {
    if (err.status === 404) {
      res.status(404).json({ error: err.message || "Appcast not found" });
      return;
    }
    next(err);
  }
}

app.get("/appcast.xml", serveAppcast);
app.get("/api/v1/plugins/:pluginId/appcast.xml", serveAppcast);

app.get("/api/v1/plugins", async (_req, res, next) => {
  try {
    const plugins = (await listPlugins()).map(withPublicDownloadUrls);
    res.json({ plugins });
  } catch (err) {
    next(err);
  }
});

app.get("/api/v1/plugins/:pluginId/versions", async (req, res, next) => {
  try {
    const versions = await listPluginVersions(req.params.pluginId);
    res.json({
      pluginId: req.params.pluginId,
      count: versions.length,
      versions: versions.map(withPublicDownloadUrls),
    });
  } catch (err) {
    next(err);
  }
});

app.get("/api/v1/plugins/:pluginId/versions/latest", async (req, res, next) => {
  try {
    const channel = normalizeChannel(req.query.channel);
    const version = await getLatestPluginVersion(req.params.pluginId, { channel });
    if (!version) {
      res.status(404).json({ error: "No versions found for plugin" });
      return;
    }
    res.json(withPublicDownloadUrls({ ...version, channel: version.channel || channel }));
  } catch (err) {
    next(err);
  }
});

app.get("/api/v1/plugins/:pluginId/versions/:version", async (req, res, next) => {
  try {
    const version = await getPluginVersion(req.params.pluginId, req.params.version);
    if (!version) {
      res.status(404).json({ error: "Version not found" });
      return;
    }
    res.json(withPublicDownloadUrls(version));
  } catch (err) {
    next(err);
  }
});

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: err.message || "Internal server error" });
});

app.listen(port, () => {
  console.log(`registry-api listening on :${port}`);
});
