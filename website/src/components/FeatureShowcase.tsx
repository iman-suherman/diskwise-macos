import { BRAND_NAME } from "@/lib/brand";

const coreFeatures = [
  {
    title: "Disk Analysis",
    description:
      "Scan internal or external drives, resume saved scans, and explore Overview, Breakdown, History, Schedule, and Insights tabs. Fast scans get you started quickly; Deep Scan maps protected folders for a fuller picture.",
    icon: "💾",
    tint: "bg-brand-blue/15 text-brand-blue",
  },
  {
    title: "System Optimization",
    description:
      "A single health score blends CPU, memory, and disk headroom. Tabs for System Status, Memory Analyzer, Issue History, Apple Intelligence, and Process Usage keep performance monitoring in one place.",
    icon: "📈",
    tint: "bg-brand-blueLight/15 text-brand-blueLight",
  },
  {
    title: "Duplicates Finder",
    description:
      "Find duplicate files — including similar videos — so you can reclaim space without guessing which copy to keep. Review groups before anything moves to Trash.",
    icon: "🔍",
    tint: "bg-brand-blueDark/25 text-brand-blue",
  },
  {
    title: "Clean My Mac",
    description:
      "Sweep app, browser, and developer caches, logs, temp files, Trash, installers, virtual environments, and project clutter like node_modules and build artifacts.",
    icon: "🧹",
    tint: "bg-brand-charcoal/50 text-brand-blueLight",
  },
  {
    title: "System Cleanup",
    description:
      "Go deeper with Time Machine snapshot management, complete app removal, and system-level optimization tasks beyond everyday cache clearing.",
    icon: "⚙️",
    tint: "bg-brand-blue/15 text-brand-blue",
  },
  {
    title: "Startup Apps",
    description:
      "Review Open at Login items, Dock apps, and Launch Agents. DiskWise flags optional startup items and explains which ones you can safely disable to speed boot and cut background memory use.",
    icon: "🚀",
    tint: "bg-brand-blueLight/15 text-brand-blueLight",
  },
  {
    title: "Activity Log",
    description:
      "A running record of scans, cleanups, and system events so you always know what DiskWise did and when — helpful for peace of mind after a big cleanup session.",
    icon: "📋",
    tint: "bg-brand-blueDark/25 text-brand-blue",
  },
  {
    title: "Menu Bar monitor",
    description:
      "Show free space and health score in the menu bar, pick which drives to watch, and keep external disks awake when you need always-on access.",
    icon: "📡",
    tint: "bg-brand-charcoal/50 text-brand-blueLight",
  },
];

const workflowSteps = [
  {
    title: "Scan & analyze",
    description:
      "Pick a drive or cleanup category. DiskWise classifies storage, scores system health, and saves results so you can pick up where you left off — as shown by “Loaded saved scan for Macintosh HD.”",
  },
  {
    title: "Review with evidence",
    description:
      "Explore breakdown charts, memory trends, duplicate groups, startup recommendations, and AI summaries. Every suggestion links back to real numbers from your Mac.",
  },
  {
    title: "Clean safely",
    description:
      "Preview reclaimable items, confirm what moves to Trash, and undo if needed. DiskWise never permanently deletes by default — you stay in control.",
  },
];

const alsoIncluded = [
  {
    title: "Scheduled scans",
    description: "Plan recurring disk scans from the Disk Analysis Schedule tab.",
    icon: "🗓️",
  },
  {
    title: "AI you choose",
    description: "Apple Intelligence on supported Macs, or connect Ollama / LM Studio in Settings.",
    icon: "✨",
  },
  {
    title: "Saved scan history",
    description: "Resume prior scans instead of waiting through a full crawl every time.",
    icon: "💿",
  },
  {
    title: "Simple install",
    description: "Download the DMG, drag DiskWise to Applications, and launch — standard macOS setup.",
    icon: "📦",
  },
];

export function FeatureShowcase() {
  return (
    <section id="features" className="mx-auto max-w-7xl px-4 py-6 sm:px-6 sm:py-8 md:py-10">
      <div className="mx-auto max-w-3xl text-center">
        <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
          Everything in one app
        </p>
        <h2 className="mt-2 text-2xl font-bold text-slate-50 sm:text-3xl md:text-4xl">
          More than a disk chart — {BRAND_NAME} is your Mac maintenance hub.
        </h2>
        <p className="mt-4 text-base leading-7 text-slate-400">
          The sidebar in DiskWise lists every major tool in plain language. You do not need a
          separate duplicate finder, cache cleaner, or activity monitor — they are already built in,
          with AI help when you want a second opinion.
        </p>
      </div>

      <ul className="mt-10 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {coreFeatures.map((item) => (
          <li key={item.title} className="card p-5">
            <div
              className={`inline-flex h-11 w-11 items-center justify-center rounded-xl text-lg ${item.tint}`}
            >
              {item.icon}
            </div>
            <h3 className="mt-4 text-lg font-semibold text-slate-100">{item.title}</h3>
            <p className="mt-2 text-sm leading-6 text-slate-400">{item.description}</p>
          </li>
        ))}
      </ul>

      <div className="mt-10 sm:mt-12">
        <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
          How it works
        </p>
        <p className="mt-2 max-w-2xl text-slate-400">
          From first launch to reclaimed gigabytes — with preview and undo at every step.
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
        {alsoIncluded.map((item) => (
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
