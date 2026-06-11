const fs = require("node:fs");
const { absoluteLogPath } = require("./deploy-store.cjs");

function sanitizeTerminal(text) {
  return String(text)
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/[\x00-\x08\x0b\x1a]/g, "");
}

function parseLogContent(content) {
  return sanitizeTerminal(content)
    .split("\n")
    .map((line) => line.trimEnd())
    .filter((line) => line.trim() && !line.startsWith("#"));
}

function readMeaningfulLines(logFile) {
  if (!logFile) return [];
  const abs = absoluteLogPath(logFile);
  if (!fs.existsSync(abs)) return [];
  try {
    return parseLogContent(fs.readFileSync(abs, "utf8"));
  } catch {
    return [];
  }
}

function lastLogLine(logFile) {
  const lines = readMeaningfulLines(logFile);
  return lines.length > 0 ? lines[lines.length - 1] : null;
}

function tailLogLines(logFile, maxLines = 12) {
  const lines = readMeaningfulLines(logFile);
  if (lines.length <= maxLines) return lines;
  return lines.slice(-maxLines);
}

module.exports = {
  lastLogLine,
  tailLogLines,
  sanitizeTerminal,
};
