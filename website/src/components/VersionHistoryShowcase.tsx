import Link from "next/link";

export function VersionHistoryShowcase() {
  return (
    <section id="version-history" className="mx-auto max-w-7xl px-4 py-6 sm:px-6 sm:py-8 md:py-10">
      <div className="flex justify-center">
        <Link href="/versions" className="btn-primary">
          Browse all releases
        </Link>
      </div>
    </section>
  );
}
