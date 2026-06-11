import { BRAND_NAME, GITHUB_ISSUES_URL, GITHUB_REPO_URL } from "@/lib/brand";

const waysToHelp = [
  {
    title: "Report a bug or request a feature",
    description:
      "Found something broken or have an idea? Open a GitHub issue with steps to reproduce, screenshots, or a short description of what you need.",
    href: GITHUB_ISSUES_URL,
    cta: "Open an issue",
  },
  {
    title: "Contribute code or docs",
    description:
      "Pull requests are welcome — whether you fix a scanner edge case, improve SwiftUI, tighten tests, or polish documentation for other macOS developers.",
    href: GITHUB_REPO_URL,
    cta: "View the repository",
  },
];

export function OpenSourceSection() {
  return (
    <section id="opensource" className="mx-auto max-w-7xl px-4 py-6 sm:px-6 sm:py-8 md:py-10">
      <div className="rounded-2xl border border-white/10 bg-white/[0.03] px-5 py-6 sm:rounded-[2rem] sm:px-8 sm:py-8 md:px-10">
        <div className="max-w-3xl">
          <p className="text-sm font-semibold uppercase tracking-wide text-brand-purple">
            Open source
          </p>
          <h2 className="mt-2 text-2xl font-bold text-slate-50 sm:text-3xl md:text-4xl">
            Built in the open. Better with your help.
          </h2>
          <p className="mt-4 text-base leading-7 text-slate-400">
            {BRAND_NAME} is an open source project. The full macOS app, Swift packages, database
            layer, and marketing site live on GitHub — inspect the code, run it locally, and shape
            what comes next.
          </p>
          <a
            href={GITHUB_REPO_URL}
            className="mt-4 inline-flex items-center gap-2 text-base font-semibold text-brand-blue transition hover:text-[#3395ff]"
            target="_blank"
            rel="noopener noreferrer"
          >
            <GitHubIcon />
            github.com/iman-suherman/diskwise-macos
          </a>
        </div>

        <div className="mt-8 grid gap-5 md:grid-cols-2">
          {waysToHelp.map((item) => (
            <article
              key={item.title}
              className="rounded-2xl border border-white/10 bg-black/20 p-5 sm:p-6"
            >
              <h3 className="text-lg font-semibold text-slate-100">{item.title}</h3>
              <p className="mt-2 text-sm leading-6 text-slate-400">{item.description}</p>
              <a
                href={item.href}
                className="btn-secondary mt-4 inline-flex"
                target="_blank"
                rel="noopener noreferrer"
              >
                {item.cta}
              </a>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function GitHubIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden>
      <path
        fill="currentColor"
        d="M12 0C5.37 0 0 5.37 0 12c0 5.3 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61-.546-1.387-1.333-1.756-1.333-1.756-1.09-.745.083-.73.083-.73 1.205.085 1.84 1.237 1.84 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.605-2.665-.303-5.466-1.332-5.466-5.93 0-1.31.468-2.38 1.236-3.22-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23a11.5 11.5 0 0 1 3.003-.404c1.02.005 2.047.138 3.003.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.91 1.235 3.22 0 4.61-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222 0 1.606-.015 2.898-.015 3.293 0 .322.216.694.825.576C20.565 21.796 24 17.297 24 12c0-6.63-5.37-12-12-12Z"
      />
    </svg>
  );
}
