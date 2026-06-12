"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { LocalReleaseDate } from "@/components/LocalReleaseDate";
import { useAllVersions } from "@/hooks/useRegistry";
import {
  flattenReleaseNotes,
  formatBytes,
  publishedAtToIso,
  toPublicDownloadUrl,
  type AppVersion,
} from "@/lib/registry";

const PAGE_SIZE = 10;

function ReleaseCard({
  version,
  isLatest,
}: {
  version: AppVersion;
  isLatest: boolean;
}) {
  const notes = flattenReleaseNotes(version.releaseNotes).slice(0, 4);
  const releasedAtIso = publishedAtToIso(version.publishedAt);

  return (
    <article className="card p-6">
      <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div>
          <div className="flex items-center gap-3">
            <h3 className="text-xl font-semibold text-slate-100">v{version.version}</h3>
            {isLatest && (
              <span className="rounded-full bg-brand-blue/15 px-2 py-0.5 text-xs font-semibold text-brand-blue">
                Latest
              </span>
            )}
          </div>
          <p className="mt-2 text-sm text-slate-400">
            {version.summary ?? "DiskWise release"}
          </p>
          <p className="mt-2 text-xs text-slate-500">
            {releasedAtIso ? (
              <>
                <LocalReleaseDate iso={releasedAtIso} />
                {" · "}
                {formatBytes(version.sizeBytes)}
              </>
            ) : (
              <>Released — · {formatBytes(version.sizeBytes)}</>
            )}
          </p>
          {notes.length > 0 && (
            <ul className="mt-4 space-y-1 text-sm text-slate-400">
              {notes.map((note) => (
                <li key={note}>• {note}</li>
              ))}
            </ul>
          )}
        </div>
        <a href={toPublicDownloadUrl(version)} className="btn-primary shrink-0">
          Download DMG
        </a>
      </div>
    </article>
  );
}

function LoadingSkeleton() {
  return (
    <div className="mt-6 space-y-4" aria-busy="true" aria-label="Loading releases">
      {[0, 1, 2].map((key) => (
        <div key={key} className="card p-6">
          <div className="h-6 w-24 animate-pulse rounded bg-slate-700" />
          <div className="mt-3 h-4 w-2/3 animate-pulse rounded bg-slate-800" />
          <div className="mt-2 h-3 w-1/3 animate-pulse rounded bg-slate-800" />
        </div>
      ))}
    </div>
  );
}

function Pagination({
  currentPage,
  totalPages,
  totalCount,
  onPageChange,
}: {
  currentPage: number;
  totalPages: number;
  totalCount: number;
  onPageChange: (page: number) => void;
}) {
  const start = (currentPage - 1) * PAGE_SIZE + 1;
  const end = Math.min(currentPage * PAGE_SIZE, totalCount);

  return (
    <nav
      className="mt-8 flex flex-col gap-4 border-t border-white/10 pt-6 sm:flex-row sm:items-center sm:justify-between"
      aria-label="Release pagination"
    >
      <p className="text-sm text-slate-400">
        Showing {start}–{end} of {totalCount} releases
      </p>
      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={() => onPageChange(currentPage - 1)}
          disabled={currentPage <= 1}
          className="btn-secondary disabled:cursor-not-allowed disabled:opacity-50"
          aria-label="Previous page"
        >
          Previous
        </button>
        <span className="px-2 text-sm font-medium text-slate-300">
          Page {currentPage} of {totalPages}
        </span>
        <button
          type="button"
          onClick={() => onPageChange(currentPage + 1)}
          disabled={currentPage >= totalPages}
          className="btn-secondary disabled:cursor-not-allowed disabled:opacity-50"
          aria-label="Next page"
        >
          Next
        </button>
      </div>
    </nav>
  );
}

export function VersionHistory() {
  const { data: versions, loading } = useAllVersions();
  const searchParams = useSearchParams();
  const router = useRouter();

  const totalCount = versions.length;
  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));
  const rawPage = Number.parseInt(searchParams.get("page") ?? "1", 10);
  const currentPage =
    Number.isFinite(rawPage) && rawPage >= 1 ? Math.min(rawPage, totalPages) : 1;
  const pageVersions = versions.slice(
    (currentPage - 1) * PAGE_SIZE,
    currentPage * PAGE_SIZE,
  );

  function goToPage(page: number) {
    const nextPage = Math.max(1, Math.min(page, totalPages));
    const params = new URLSearchParams(searchParams.toString());
    if (nextPage <= 1) {
      params.delete("page");
    } else {
      params.set("page", String(nextPage));
    }
    const query = params.toString();
    router.push(query ? `/versions?${query}` : "/versions", { scroll: false });
  }

  return (
    <section id="versions" className="mx-auto max-w-7xl px-4 py-8 sm:px-6 sm:py-10">
      <div>
        <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
          All releases
        </p>
        <h2 className="mt-2 text-3xl font-bold text-slate-50">Download any version</h2>
        <p className="mt-2 max-w-2xl text-slate-400">
          Browse past releases, read what changed, and grab the DMG you need.
        </p>
      </div>

      {loading ? (
        <LoadingSkeleton />
      ) : versions.length === 0 ? (
        <div className="card mt-6 p-8 text-center text-slate-400">
          No releases are available yet. Check back soon for the first download.
        </div>
      ) : (
        <>
          <div className="mt-6 space-y-4">
            {pageVersions.map((version, index) => (
              <ReleaseCard
                key={version.version}
                version={version}
                isLatest={currentPage === 1 && index === 0}
              />
            ))}
          </div>
          {totalPages > 1 && (
            <Pagination
              currentPage={currentPage}
              totalPages={totalPages}
              totalCount={totalCount}
              onPageChange={goToPage}
            />
          )}
        </>
      )}
    </section>
  );
}
