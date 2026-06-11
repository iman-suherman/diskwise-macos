import { readFile } from "node:fs/promises";
import path from "node:path";

const APP_ID = process.env.NEXT_PUBLIC_APP_ID?.trim() || "diskwise-macos";
const REGISTRY_API_URL =
  process.env.NEXT_PUBLIC_REGISTRY_API_URL?.trim() ||
  "https://diskwise-registry.suherman.net";

async function serveLocalAppcast(): Promise<Response | null> {
  try {
    const localPath = path.join(process.cwd(), "public", "appcast.xml");
    const xml = await readFile(localPath, "utf8");
    return new Response(xml, {
      headers: {
        "Content-Type": "application/xml; charset=utf-8",
        "Cache-Control": "public, max-age=60",
      },
    });
  } catch {
    return null;
  }
}

export async function GET() {
  if (process.env.NODE_ENV === "development") {
    const local = await serveLocalAppcast();
    if (local) return local;
  }

  const feedUrl = `${REGISTRY_API_URL.replace(/\/$/, "")}/api/v1/plugins/${APP_ID}/appcast.xml`;
  const upstream = await fetch(feedUrl, { next: { revalidate: 300 } });

  if (!upstream.ok) {
    const fallback = await serveLocalAppcast();
    if (fallback) return fallback;
    return new Response("Appcast feed unavailable", { status: upstream.status });
  }

  const xml = await upstream.text();
  return new Response(xml, {
    headers: {
      "Content-Type": "application/xml; charset=utf-8",
      "Cache-Control": "public, max-age=300",
    },
  });
}
