import { BRAND_NAME } from "@/lib/brand";

const highlights = [
  {
    title: "Everything stays on your Mac",
    description: "Scans, metadata extraction, and duplicate detection run locally — no cloud upload.",
    icon: "💻",
    tint: "bg-brand-blue/15 text-brand-blue",
  },
  {
    title: "Optional local AI",
    description: "Connect Ollama or LM Studio for reports — still fully on-device when enabled.",
    icon: "🤖",
    tint: "bg-brand-purple/15 text-brand-purple",
  },
  {
    title: "You stay in control",
    description: "Grant Full Disk Access only when needed, with clear explanations in the app.",
    icon: "🔒",
    tint: "bg-brand-green/15 text-brand-green",
  },
];

const privacyChecks = [
  "No path or content upload",
  "On-device SQLite database",
  "Trash-first cleanup workflow",
  "Transparent permissions",
];

export function PrivacySection() {
  return (
    <section id="privacy" className="mx-auto max-w-7xl px-4 py-6 sm:px-6 sm:py-8 md:py-10">
      <div className="grid gap-8 lg:grid-cols-2 lg:items-center">
        <div>
          <p className="text-sm font-semibold uppercase tracking-wide text-brand-green">
            Private by design
          </p>
          <h2 className="mt-2 text-2xl font-bold text-slate-50 sm:mt-3 sm:text-3xl md:text-4xl">
            Intelligent analysis without sending your files to the cloud.
          </h2>
          <p className="mt-4 max-w-xl text-sm leading-6 text-slate-400 sm:text-base sm:leading-7">
            Your storage data is yours. {BRAND_NAME} is designed as a private consultant, not a
            data collection service — no accounts, no telemetry, and no path or file content upload
            by default.
          </p>
          <p className="mt-4 max-w-xl text-sm leading-6 text-slate-400 sm:text-base sm:leading-7">
            Volume scans, classifications, duplicate hashes, and recommendations are indexed in a
            local SQLite database on your Mac. Optional Ollama or LM Studio reports stay on-device
            when you connect them. Cleanup always previews what will move to Trash before you
            confirm, and Full Disk Access is requested only when broader visibility is needed —
            with clear explanations in the app.
          </p>
        </div>

        <div>
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

          <div className="mt-6 rounded-2xl border border-brand-green/20 bg-brand-green/10 p-5">
            <p className="flex items-center gap-2 text-sm font-semibold text-brand-green">
              <span aria-hidden>🛡️</span>
              Privacy first
            </p>
            <ul className="mt-3 grid gap-2 sm:grid-cols-2">
              {privacyChecks.map((item) => (
                <li key={item} className="flex items-center gap-2 text-sm text-slate-300">
                  <span className="text-brand-green" aria-hidden>
                    ✓
                  </span>
                  {item}
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    </section>
  );
}
