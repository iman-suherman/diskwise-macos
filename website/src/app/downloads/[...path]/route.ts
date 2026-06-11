import fs from "node:fs";
import path from "node:path";
import { NextResponse } from "next/server";

const websiteRoot = process.cwd();
const repoRoot = path.join(websiteRoot, "..");
const publicDownloadsDir = path.join(websiteRoot, "public", "downloads");
const releasesDir = path.join(repoRoot, "releases");
const sparkleDir = path.join(releasesDir, "sparkle");

const CONTENT_TYPES: Record<string, string> = {
  ".dmg": "application/x-apple-diskimage",
  ".zip": "application/zip",
  ".delta": "application/octet-stream",
};

function contentTypeFor(fileName: string): string {
  const ext = path.extname(fileName).toLowerCase();
  return CONTENT_TYPES[ext] ?? "application/octet-stream";
}

function resolveLatestDmg(): string | null {
  if (!fs.existsSync(releasesDir)) return null;

  const dmgs = fs
    .readdirSync(releasesDir)
    .filter((name) => name.endsWith(".dmg") && name.startsWith("diskwise-macos-"))
    .map((name) => ({
      name,
      fullPath: path.join(releasesDir, name),
      mtimeMs: fs.statSync(path.join(releasesDir, name)).mtimeMs,
    }))
    .sort((left, right) => right.mtimeMs - left.mtimeMs);

  return dmgs[0]?.fullPath ?? null;
}

function resolveDownloadFile(fileName: string): string | null {
  const safeName = path.basename(fileName);
  if (safeName !== fileName || safeName.includes("..")) {
    return null;
  }

  if (safeName === "latest.dmg") {
    return resolveLatestDmg();
  }

  const candidates = [
    path.join(publicDownloadsDir, safeName),
    path.join(releasesDir, safeName),
    path.join(sparkleDir, safeName),
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
      return candidate;
    }
  }

  return null;
}

export async function GET(
  _request: Request,
  context: { params: Promise<{ path: string[] }> },
) {
  const { path: segments } = await context.params;
  const fileName = segments?.join("/") ?? "";
  const resolved = resolveDownloadFile(fileName);

  if (!resolved) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const data = fs.readFileSync(resolved);
  const downloadName = fileName === "latest.dmg" ? path.basename(resolved) : path.basename(resolved);

  return new NextResponse(data, {
    headers: {
      "Content-Type": contentTypeFor(downloadName),
      "Content-Length": String(data.byteLength),
      "Content-Disposition": `attachment; filename="${downloadName}"`,
      "Cache-Control": "no-store",
    },
  });
}
