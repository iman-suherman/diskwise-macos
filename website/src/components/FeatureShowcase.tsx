import { BRAND_NAME } from "@/lib/brand";

const highlights = [
  {
    title: "Scan any volume",
    description: "Crawl internal drives and external volumes like /Volumes/Media01 with incremental progress.",
    icon: "💾",
    tint: "bg-brand-blue/15 text-brand-blue",
  },
  {
    title: "Find duplicates",
    description: "Detect duplicates by filename, size, SHA256 hash, and video fingerprinting.",
    icon: "🔍",
    tint: "bg-brand-purple/15 text-brand-purple",
  },
  {
    title: "AI chat & recommendations",
    description:
      "Ask DiskWise what is using your disk, then review ranked cleanup suggestions for caches, old DMGs, and stale files.",
    icon: "✨",
    tint: "bg-brand-orange/15 text-brand-orange",
  },
  {
    title: "Safe cleanup",
    description: "Preview every action and move files to Trash — never permanent deletion by default.",
    icon: "🗑️",
    tint: "bg-brand-green/15 text-brand-green",
  },
];

const workflowSteps = [
  {
    title: "Scan",
    description: "Select a volume and let DiskWise classify files across your storage.",
  },
  {
    title: "Review",
    description: "Explore storage breakdowns, duplicate groups, AI chat, and safe cleanup suggestions.",
  },
  {
    title: "Reclaim",
    description: "Preview cleanup and move selected files to Trash with undo-friendly workflow.",
  },
];

const footerHighlights = [
  { title: "SwiftUI native", description: "Fast, responsive macOS experience.", icon: "🍎" },
  { title: "SQLite + GRDB", description: "Persistent scan history on device.", icon: "📊" },
  { title: "Optional Ollama", description: "Local LLM reports when you want them.", icon: "🤖" },
  { title: "Modular kits", description: "Scanner, metadata, duplicates, cleanup, AI.", icon: "🧩" },
];

export function FeatureShowcase() {
  return (
    <section id="features" className="mx-auto max-w-7xl px-4 py-6 sm:px-6 sm:py-8 md:py-10">
      <div className="grid gap-8 lg:grid-cols-2 lg:items-center lg:gap-12">
        <ul className="space-y-4">
          {highlights.map((item) => (
            <li key={item.title} className="flex gap-4">
              <div
                className={`inline-flex h-12 w-12 shrink-0 items-center justify-center rounded-xl text-xl ${item.tint}`}
              >
                {item.icon}
              </div>
              <div>
                <h3 className="text-lg font-semibold text-slate-100">{item.title}</h3>
                <p className="mt-1 text-sm leading-6 text-slate-400">{item.description}</p>
              </div>
            </li>
          ))}
        </ul>

        <div className="lg:pl-2">
          <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
            Intelligent storage analysis
          </p>
          <h2 className="mt-2 text-2xl font-bold text-slate-50 sm:mt-3 sm:text-3xl md:text-4xl">
            More than a treemap — {BRAND_NAME} acts as your AI storage consultant.
          </h2>
          <p className="mt-4 max-w-xl text-sm leading-6 text-slate-400 sm:text-base sm:leading-7">
            {BRAND_NAME} goes beyond folder sizes and pie charts. It classifies storage into
            meaningful categories, surfaces duplicate videos and stale exports, and estimates how
            much space you can safely reclaim — with plain-language guidance instead of raw numbers
            alone.
          </p>
          <p className="mt-4 max-w-xl text-sm leading-6 text-slate-400 sm:text-base sm:leading-7">
            Scan internal or external volumes, review ranked hotspots and recommended actions, then
            preview cleanup before anything moves to Trash. Every step stays on your Mac, backed by
            modular Swift kits for scanning, metadata, duplicates, cleanup, and optional local AI.
          </p>
        </div>
      </div>

      <div className="mt-6 sm:mt-8">
        <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
          How it works
        </p>
        <p className="mt-2 max-w-2xl text-slate-400">
          From first scan to reclaimed gigabytes in three straightforward steps.
        </p>

        <ol className="mt-6 grid gap-4 md:grid-cols-3">
          {workflowSteps.map((step, index) => (
            <li key={step.title} className="card p-5">
              <span className="inline-flex h-8 w-8 items-center justify-center rounded-full bg-brand-blue/15 text-sm font-bold text-brand-blue">
                {index + 1}
              </span>
              <h3 className="mt-4 text-lg font-semibold text-slate-100">{step.title}</h3>
              <p className="mt-2 text-sm leading-6 text-slate-400">{step.description}</p>
            </li>
          ))}
        </ol>
      </div>

      <div className="mt-4 grid gap-3 sm:mt-6 sm:grid-cols-2 xl:grid-cols-4">
        {footerHighlights.map((item) => (
          <div
            key={item.title}
            className="rounded-2xl border border-white/10 bg-white/[0.04] px-5 py-4 shadow-soft"
          >
            <p className="flex items-center gap-2 text-sm font-semibold text-slate-100">
              <span aria-hidden>{item.icon}</span>
              {item.title}
            </p>
            <p className="mt-1 text-sm text-slate-400">{item.description}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
