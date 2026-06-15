import Image from "next/image";
import { BRAND_NAME } from "@/lib/brand";

type PreviewEvidence = {
  label: string;
  value: string;
};

type AppPreviewItem = {
  image: string;
  width: number;
  height: number;
  alt: string;
  eyebrow: string;
  headline: string;
  description: string;
  evidence: PreviewEvidence[];
  imageFirst?: boolean;
};

const previews: AppPreviewItem[] = [
  {
    image: "/screenshot-disk-analysis.png",
    width: 1024,
    height: 627,
    alt: `${BRAND_NAME} Disk Analysis breakdown showing storage by type with a donut chart and deep scan guidance`,
    eyebrow: "Disk Analysis",
    headline: "See where your space actually goes — not just a single “Other” bar.",
    description:
      "Scan Macintosh HD or any connected drive, then open the Breakdown tab for a clear picture of Applications, Media, Documents, Archives, Caches, and more. The app tells you when a fast scan has only mapped part of your disk and walks you through granting Full Disk Access and running a Deep Scan for fuller coverage.",
    evidence: [
      { label: "Indexed in scan", value: "486.2 GB mapped" },
      { label: "Largest category", value: "Other · 72% (353.6 GB)" },
      { label: "Also tracked", value: "Apps, Media, Docs, Caches" },
    ],
    imageFirst: true,
  },
  {
    image: "/screenshot-system-health.png",
    width: 1024,
    height: 627,
    alt: `${BRAND_NAME} System Optimization dashboard with health score and CPU, memory, and disk pressure`,
    eyebrow: "System Optimization",
    headline: "One health score that turns raw numbers into a plain answer.",
    description:
      "Instead of guessing whether your Mac is fine, DiskWise gives you a single score — for example Fair (43) — and shows exactly how CPU, memory, and disk headroom contribute. You see live pressure labels like “Low,” “Moderate,” and “High,” plus a rating scale that explains what each band means for everyday use.",
    evidence: [
      { label: "Health score", value: "Fair (43)" },
      { label: "Memory pressure", value: "70.1% · Moderate" },
      { label: "Disk headroom", value: "187.97 GB free · High pressure" },
    ],
    imageFirst: false,
  },
  {
    image: "/screenshot-memory-analyzer.png",
    width: 1024,
    height: 627,
    alt: `${BRAND_NAME} Memory Analyzer with pressure gauges, trend chart, and suggested actions`,
    eyebrow: "Memory Analyzer",
    headline: "Find what is eating RAM — and fix it in one click.",
    description:
      "The Memory Analyzer tracks current, average, and peak memory pressure over time, then lists your biggest memory consumers by name and size. When something like Ollama or Chrome is hogging RAM, DiskWise suggests a specific action — restart the app, trim tabs, or focus it — with buttons right in the interface.",
    evidence: [
      { label: "Top memory use", value: "Ollama · 4.81 GB" },
      { label: "Suggested fix", value: "Restart Ollama" },
      { label: "Also flagged", value: "Trim Google Chrome tabs" },
    ],
    imageFirst: true,
  },
  {
    image: "/screenshot-apple-intelligence.png",
    width: 1024,
    height: 627,
    alt: `${BRAND_NAME} Apple Intelligence insights summarizing memory state and top consumers`,
    eyebrow: "Apple Intelligence",
    headline: "On-device AI that explains your Mac in everyday language.",
    description:
      "The Apple Intelligence tab turns live metrics into a readable report: current memory state, recent trends, and a ranked list of apps using the most RAM — with average and peak usage spelled out. You can ask follow-up questions without sending your files to the cloud; analysis stays on your Mac.",
    evidence: [
      { label: "Analysis mode", value: "On-device · Apple Intelligence" },
      { label: "Report includes", value: "Trends + top consumers" },
      { label: "Example insight", value: "Ollama · 4.5 GB avg" },
    ],
    imageFirst: false,
  },
  {
    image: "/screenshot-clean-my-mac.png",
    width: 1024,
    height: 627,
    alt: `${BRAND_NAME} Clean My Mac screen with cache categories and Scan Now button`,
    eyebrow: "Clean My Mac",
    headline: "Targeted cleanup for caches, logs, Trash, and dev clutter.",
    description:
      "Choose what to clean from a row of focused categories — App Caches, Browser Caches, Developer Caches, Logs, Temporary Files, Trash, node_modules, Build Artifacts, and more. Tap Scan Now to find reclaimable space, review every item, and move only what you approve to Trash.",
    evidence: [
      { label: "Safety note in app", value: "Always preview before Trash" },
      { label: "Example scan result", value: "149 items · 733.3 MB" },
      { label: "Developer-friendly", value: "node_modules · build artifacts" },
    ],
    imageFirst: true,
  },
  {
    image: "/screenshot-process-usage.png",
    width: 1024,
    height: 627,
    alt: `${BRAND_NAME} Process Usage showing top CPU and memory consumers in real time`,
    eyebrow: "Process Usage",
    headline: "See what is slowing your Mac right now.",
    description:
      "The Process Usage tab ranks live CPU and memory consumers side by side — WindowServer, Chrome, Ollama, Cursor, and others — with percentages and process IDs when you need detail. Turn on Monitoring to keep an eye on pressure while you work, then hit Re-analyze when you want a fresh health score.",
    evidence: [
      { label: "Top CPU", value: "WindowServer · 38.0%" },
      { label: "Top memory", value: "Ollama · 4.76 GB" },
      { label: "Live mode", value: "Monitoring · Refresh · Re-analyze" },
    ],
    imageFirst: false,
  },
  {
    image: "/screenshot-startup-apps.png",
    width: 1024,
    height: 627,
    alt: `${BRAND_NAME} Startup Apps list with login items and AI guidance to disable optional apps`,
    eyebrow: "Startup Apps",
    headline: "Speed up boot by reviewing what opens at login.",
    description:
      "DiskWise inventories Open at Login items, Dock apps, and Launch Agents, then summarizes how many you could disable or review. Each entry gets a plain recommendation — Keep at login, Optional, or Remove — with one-click actions and a permissions panel that explains why access is needed, all processed locally.",
    evidence: [
      { label: "Items found", value: "56 startup items" },
      { label: "Open at login", value: "21 apps" },
      { label: "AI guidance", value: "Disable optional login items" },
    ],
    imageFirst: true,
  },
  {
    image: "/screenshot-menu-bar.png",
    width: 1024,
    height: 627,
    alt: `${BRAND_NAME} Menu Bar settings for drive monitoring and keeping disks awake`,
    eyebrow: "Menu Bar & drives",
    headline: "Keep an eye on every drive from the menu bar.",
    description:
      "Choose which volumes appear in the menu bar, optionally show free space and your health score at a glance, and prevent selected drives from sleeping — useful for external storage and NAS mounts. In the screenshot, DiskWise is keeping nine drives awake while monitoring internal and external storage together.",
    evidence: [
      { label: "Drives managed", value: "9 drives kept awake" },
      { label: "Menu bar option", value: "Free space + health score" },
      { label: "Works with", value: "Internal + external volumes" },
    ],
    imageFirst: false,
  },
];

function EvidenceList({ items }: { items: PreviewEvidence[] }) {
  return (
    <ul className="mt-5 space-y-2">
      {items.map((item) => (
        <li
          key={item.label}
          className="flex flex-col gap-0.5 rounded-xl border border-white/8 bg-white/[0.03] px-4 py-3 sm:flex-row sm:items-center sm:justify-between"
        >
          <span className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            {item.label}
          </span>
          <span className="text-sm font-medium text-slate-200">{item.value}</span>
        </li>
      ))}
    </ul>
  );
}

function imageWrapperClass() {
  return "relative mx-auto w-full max-w-3xl sm:max-w-4xl lg:mx-0 lg:max-w-none";
}

export function AppPreview() {
  return (
    <section id="preview" className="mx-auto max-w-7xl px-4 py-6 sm:px-6 sm:py-8 md:py-10">
      <div className="mx-auto max-w-3xl text-center">
        <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
          See it in the app
        </p>
        <h2 className="mt-2 text-2xl font-bold text-slate-50 sm:text-3xl md:text-4xl">
          Every major feature, with real screenshots from DiskWise.
        </h2>
        <p className="mt-3 text-base leading-7 text-slate-400">
          {BRAND_NAME} combines disk scanning, system health, safe cleanup, and AI guidance in one
          sidebar — the same tools you see below ship in every download.
        </p>
      </div>

      <div className="mt-10 space-y-12 lg:space-y-20">
        {previews.map((preview) => (
          <article
            key={preview.image}
            className={`grid items-center gap-8 lg:grid-cols-[1.15fr_0.85fr] lg:gap-12 ${
              preview.imageFirst ? "" : "lg:[&>div:first-child]:order-2 lg:[&>div:last-child]:order-1"
            }`}
          >
            <div className={imageWrapperClass()}>
              <div className="absolute -inset-6 rounded-full bg-gradient-to-br from-brand-blue/12 via-brand-blueDark/8 to-transparent blur-3xl" />
              <div className="relative rounded-[1.35rem] sm:rounded-[1.5rem]">
                <div className="relative overflow-hidden rounded-xl shadow-[0_4px_14px_rgba(0,0,0,0.55),0_20px_48px_rgba(0,0,0,0.5),0_40px_80px_rgba(0,0,0,0.4)] sm:rounded-2xl">
                  <Image
                    src={preview.image}
                    alt={preview.alt}
                    width={preview.width}
                    height={preview.height}
                    unoptimized
                    sizes="(max-width: 1024px) 100vw, 42rem"
                    className="relative block h-auto w-full object-contain"
                  />
                  <div
                    aria-hidden
                    className="pointer-events-none absolute inset-0 rounded-xl bg-[linear-gradient(to_bottom,rgba(0,0,0,0.18)_0%,transparent_28%,transparent_72%,rgba(0,0,0,0.32)_100%)] sm:rounded-2xl"
                  />
                  <div
                    aria-hidden
                    className="pointer-events-none absolute inset-0 rounded-xl shadow-[inset_0_1px_0_rgba(255,255,255,0.07),inset_0_-20px_40px_rgba(0,0,0,0.22)] sm:rounded-2xl"
                  />
                </div>
              </div>
            </div>

            <div className={preview.imageFirst ? "lg:pl-2" : "lg:pr-2"}>
              <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
                {preview.eyebrow}
              </p>
              <h3 className="mt-2 text-2xl font-bold text-slate-50 sm:mt-3 sm:text-3xl md:text-4xl">
                {preview.headline}
              </h3>
              <p className="mt-4 max-w-xl text-sm leading-6 text-slate-400 sm:text-base sm:leading-7">
                {preview.description}
              </p>
              <EvidenceList items={preview.evidence} />
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}
