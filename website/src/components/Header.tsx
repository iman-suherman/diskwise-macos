"use client";

import Image from "next/image";
import Link from "next/link";
import { useState } from "react";
import { BRAND_NAME, GITHUB_REPO_URL } from "@/lib/brand";

const nav = [
  { href: "/", label: "Home" },
  { href: "/install", label: "Install" },
  { href: "/versions", label: "Download" },
  { href: "/versions", label: "Versions" },
  { href: "/#preview", label: "Preview" },
  { href: "/#features", label: "Features" },
  { href: "/#privacy", label: "Privacy" },
  { href: "/#opensource", label: "Open source" },
  { href: GITHUB_REPO_URL, label: "GitHub", external: true },
];

export function Header() {
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <header className="sticky top-0 z-50 border-b border-white/10 bg-[var(--background)]/85 backdrop-blur-xl">
      <div className="mx-auto flex max-w-7xl items-center justify-between gap-3 px-4 py-3 sm:px-6 sm:py-4">
        <Link href="/" className="flex min-w-0 items-center gap-2 sm:gap-3">
          <span className="icon-squircle relative flex h-10 w-10 shrink-0 items-center justify-center sm:h-12 sm:w-12">
            <Image
              src="/app-icon.png"
              alt=""
              width={1024}
              height={1024}
              priority
              sizes="48px"
              className="app-icon-mark relative h-full w-full object-contain"
            />
          </span>
          <span className="hidden truncate text-sm font-bold leading-snug tracking-tight text-slate-50 min-[420px]:block sm:max-w-xs sm:text-base lg:max-w-md lg:text-lg">
            {BRAND_NAME}
          </span>
        </Link>

        <nav className="hidden items-center gap-6 text-sm font-medium text-slate-400 md:flex lg:gap-8">
          {nav.map((item) =>
            "external" in item && item.external ? (
              <a
                key={`${item.href}-${item.label}`}
                href={item.href}
                className="transition hover:text-brand-blue"
                target="_blank"
                rel="noopener noreferrer"
              >
                {item.label}
              </a>
            ) : (
              <Link
                key={`${item.href}-${item.label}`}
                href={item.href}
                className="transition hover:text-brand-blue"
              >
                {item.label}
              </Link>
            ),
          )}
        </nav>

        <div className="flex shrink-0 items-center gap-2">
          <Link href="/install" className="btn-primary hidden md:inline-flex">
            Get DiskWise
          </Link>
          <button
            type="button"
            onClick={() => setMenuOpen((open) => !open)}
            className="inline-flex h-10 w-10 items-center justify-center rounded-lg border border-white/15 bg-white/[0.06] text-slate-200 transition hover:border-brand-blue/40 hover:text-brand-blue md:hidden"
            aria-expanded={menuOpen}
            aria-controls="mobile-nav"
            aria-label={menuOpen ? "Close menu" : "Open menu"}
          >
            {menuOpen ? (
              <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden>
                <path
                  fill="currentColor"
                  d="M6.225 4.811a1 1 0 0 1 1.414 0L12 10.586l4.425-4.775a1 1 0 1 1 1.414 1.414L13.414 12l4.425 4.775a1 1 0 0 1-1.414 1.414L12 13.414l-4.425 4.775a1 1 0 0 1-1.414-1.414L10.586 12 6.225 7.225a1 1 0 0 1 0-1.414Z"
                />
              </svg>
            ) : (
              <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden>
                <path
                  fill="currentColor"
                  d="M4 6a1 1 0 0 1 1-1h14a1 1 0 1 1 0 2H5a1 1 0 0 1-1-1Zm0 5a1 1 0 0 1 1-1h14a1 1 0 1 1 0 2H5a1 1 0 0 1-1-1Zm0 5a1 1 0 0 1 1-1h14a1 1 0 1 1 0 2H5a1 1 0 0 1-1-1Z"
                />
              </svg>
            )}
          </button>
        </div>
      </div>

      {menuOpen && (
        <nav
          id="mobile-nav"
          className="border-t border-white/10 bg-[var(--surface)] px-4 py-4 shadow-soft md:hidden"
        >
          <ul className="space-y-1">
            {nav.map((item) => (
              <li key={`${item.href}-${item.label}-mobile`}>
                {"external" in item && item.external ? (
                  <a
                    href={item.href}
                    className="block rounded-lg px-3 py-2.5 text-sm font-medium text-slate-200 transition hover:bg-brand-blue/10 hover:text-brand-blue"
                    target="_blank"
                    rel="noopener noreferrer"
                    onClick={() => setMenuOpen(false)}
                  >
                    {item.label}
                  </a>
                ) : (
                  <Link
                    href={item.href}
                    className="block rounded-lg px-3 py-2.5 text-sm font-medium text-slate-200 transition hover:bg-brand-blue/10 hover:text-brand-blue"
                    onClick={() => setMenuOpen(false)}
                  >
                    {item.label}
                  </Link>
                )}
              </li>
            ))}
          </ul>
          <Link
            href="/install"
            className="btn-primary mt-4 w-full"
            onClick={() => setMenuOpen(false)}
          >
            Get DiskWise
          </Link>
        </nav>
      )}
    </header>
  );
}
