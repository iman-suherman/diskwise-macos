import Link from "next/link";
import { BRAND_NAME } from "@/lib/brand";

/** Custom not-found — avoid Next's default "404: This page could not be found."
 *  string, which Play / Google soft-404 detectors flag even on valid pages. */
export default function NotFound() {
  return (
    <div className="mx-auto flex min-h-[60vh] max-w-lg flex-col justify-center px-4 py-24 text-center sm:px-6">
      <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
        {BRAND_NAME}
      </p>
      <h1 className="mt-3 text-3xl font-bold tracking-tight text-slate-50">
        Missing page
      </h1>
      <p className="mt-4 text-sm leading-7 text-slate-400">
        This path is not part of the DiskWise site. Try the home page or privacy
        policy instead.
      </p>
      <div className="mt-8 flex flex-wrap items-center justify-center gap-4 text-sm font-semibold">
        <Link href="/" className="text-brand-blue transition hover:text-brand-blueLight">
          Home
        </Link>
        <Link
          href="/privacy"
          className="text-brand-blue transition hover:text-brand-blueLight"
        >
          Privacy policy
        </Link>
      </div>
    </div>
  );
}
