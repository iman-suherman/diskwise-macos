export const APP_ID = process.env.NEXT_PUBLIC_APP_ID?.trim() || "diskwise-macos";

export const REGISTRY_API_URL =
  process.env.NEXT_PUBLIC_REGISTRY_API_URL?.trim() ||
  "https://diskwise-registry.suherman.net";

export const DOWNLOAD_BASE_URL =
  process.env.NEXT_PUBLIC_DOWNLOAD_BASE_URL?.trim() ||
  "https://diskwise-download.suherman.net/downloads";

export type ReleaseNotes = {
  introduced?: string[];
  changed?: string[];
  updated?: string[];
  fixed?: string[];
  removed?: string[];
  breaking?: string[];
};

export type AppVersion = {
  pluginId: string;
  displayName?: string;
  publisher?: string;
  version: string;
  summary?: string;
  releaseNotes?: ReleaseNotes;
  releaseNotesMarkdown?: string;
  downloadUrl?: string;
  publicDownloadUrl?: string;
  gcs?: {
    bucket?: string;
    objectPath?: string;
    vsixFileName?: string;
  };
  sizeBytes?: number;
  gitCommit?: string;
  publishedAt?: { _seconds?: number; seconds?: number } | string;
};

export type VersionsResponse = {
  pluginId: string;
  count: number;
  versions: AppVersion[];
};

function dmgFileName(version: AppVersion): string {
  if (version.gcs?.vsixFileName) {
    const name = version.gcs.vsixFileName;
    return name.endsWith(".dmg") ? name : name.replace(/\.vsix$/, ".dmg");
  }
  if (version.gcs?.objectPath) {
    const parts = version.gcs.objectPath.split("/");
    const last = parts[parts.length - 1];
    if (last) return last;
  }
  if (version.publicDownloadUrl) {
    try {
      const parts = new URL(version.publicDownloadUrl).pathname.split("/");
      const last = parts[parts.length - 1];
      if (last?.endsWith(".dmg")) return last;
    } catch {
      /* ignore */
    }
  }
  return `${APP_ID}-${version.version}.dmg`;
}

export function toPublicDownloadUrl(version: AppVersion): string {
  const base = DOWNLOAD_BASE_URL.replace(/\/$/, "");
  return `${base}/${dmgFileName(version)}`;
}

export function formatBytes(bytes?: number): string {
  if (!bytes) return "—";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

const RELEASE_DATE_FORMAT: Intl.DateTimeFormatOptions = {
  day: "2-digit",
  month: "short",
  year: "numeric",
};

export function formatDate(value?: AppVersion["publishedAt"]): string {
  if (!value) return "—";
  let date: Date;
  if (typeof value === "string") {
    date = new Date(value);
  } else {
    const seconds = value._seconds ?? value.seconds;
    if (!seconds) return "—";
    date = new Date(seconds * 1000);
  }
  return Number.isNaN(date.getTime())
    ? "—"
    : date.toLocaleDateString("en-GB", RELEASE_DATE_FORMAT);
}

export function publishedAtToIso(value?: AppVersion["publishedAt"]): string | null {
  if (!value) return null;
  if (typeof value === "string") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
  }
  const seconds = value._seconds ?? value.seconds;
  if (!seconds) return null;
  return new Date(seconds * 1000).toISOString();
}

export function flattenReleaseNotes(notes?: ReleaseNotes): string[] {
  if (!notes) return [];
  return [
    ...(notes.breaking ?? []).map((item) => `Breaking: ${item}`),
    ...(notes.introduced ?? []).map((item) => `Introduced: ${item}`),
    ...(notes.changed ?? []).map((item) => `Changed: ${item}`),
    ...(notes.updated ?? []).map((item) => `Updated: ${item}`),
    ...(notes.fixed ?? []).map((item) => `Fixed: ${item}`),
    ...(notes.removed ?? []).map((item) => `Removed: ${item}`),
  ];
}
