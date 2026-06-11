import Link from "next/link";
import { BRAND_NAME, GITHUB_ISSUES_URL, GITHUB_REPO_URL } from "@/lib/brand";

export function Footer() {
  return (
    <footer className="border-t border-white/10 bg-black/40">
      <div className="mx-auto max-w-7xl px-4 py-5 sm:px-6 sm:py-6">
        <p className="max-w-5xl text-sm leading-6 text-slate-400">
          {BRAND_NAME} is an open source, intelligent macOS disk analyzer and cleanup assistant.
          All scanning, duplicate detection, and AI recommendations run on your Mac — your files
          never leave your device unless you choose to sync them elsewhere. Contributions and issue
          reports are welcome on{" "}
          <a
            href={GITHUB_REPO_URL}
            className="text-brand-blue transition hover:text-[#3395ff]"
            target="_blank"
            rel="noopener noreferrer"
          >
            GitHub
          </a>
          .
        </p>

        <div className="mt-4 flex flex-col gap-4 border-t border-white/10 pt-4 text-sm text-slate-500 md:flex-row md:items-center md:justify-between">
          <p>
            © {new Date().getFullYear()} Iman Suherman. Open source on{" "}
            <a
              href={GITHUB_REPO_URL}
              className="text-brand-blue transition hover:text-[#3395ff]"
              target="_blank"
              rel="noopener noreferrer"
            >
              GitHub
            </a>
            .
          </p>
          <div className="flex flex-wrap gap-4">
            <Link href="/install" className="transition hover:text-brand-blue">
              Install guide
            </Link>
            <Link href="/versions" className="transition hover:text-brand-blue">
              Versions
            </Link>
            <Link href="/versions" className="transition hover:text-brand-blue">
              Download
            </Link>
            <a
              href={GITHUB_REPO_URL}
              className="transition hover:text-brand-blue"
              target="_blank"
              rel="noopener noreferrer"
            >
              Source code
            </a>
            <a
              href={GITHUB_ISSUES_URL}
              className="transition hover:text-brand-blue"
              target="_blank"
              rel="noopener noreferrer"
            >
              Report an issue
            </a>
          </div>
        </div>
      </div>
    </footer>
  );
}
