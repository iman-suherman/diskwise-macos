import { BRAND_NAME } from "@/lib/brand";

const highlights = [
  {
    title: "Analysis stays on your Mac",
    description:
      "Volume scans, health metrics, startup inventories, and cleanup previews are processed locally. Your file contents are not uploaded to a cloud service.",
    icon: "💻",
    tint: "bg-brand-blue/15 text-brand-blue",
  },
  {
    title: "On-device AI by default",
    description:
      "Apple Intelligence insights and optional Ollama or LM Studio reports run on your machine. You choose the AI provider in Settings — nothing leaves without your setup.",
    icon: "🤖",
    tint: "bg-brand-blueLight/15 text-brand-blueLight",
  },
  {
    title: "Transparent permissions",
    description:
      "Full Disk Access and login-item access are requested only when needed, with in-app explanations — like the Startup Apps panel that describes why each permission helps.",
    icon: "🔒",
    tint: "bg-brand-charcoal/50 text-brand-blueLight",
  },
];

const privacyChecks = [
  "No accounts required",
  "Trash-first cleanup workflow",
  "Local scan history on device",
  "Clear permission explanations",
];

export function PrivacySection() {
  return (
    <section id="privacy" className="mx-auto max-w-7xl px-4 py-6 sm:px-6 sm:py-8 md:py-10">
      <div className="grid gap-8 lg:grid-cols-2 lg:items-center">
        <div>
          <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
            Private by design
          </p>
          <h2 className="mt-2 text-2xl font-bold text-slate-50 sm:mt-3 sm:text-3xl md:text-4xl">
            Smart recommendations without sending your files to the cloud.
          </h2>
          <p className="mt-4 max-w-xl text-sm leading-6 text-slate-400 sm:text-base sm:leading-7">
            DiskWise reads your storage and system metrics to give you useful answers — like which
            apps use the most memory or which startup items you can disable. That work happens on
            your Mac, not on someone else&apos;s server.
          </p>
          <p className="mt-4 max-w-xl text-sm leading-6 text-slate-400 sm:text-base sm:leading-7">
            When you clean up, every action is previewed first and files go to Trash by default so
            you can recover them. The Activity Log keeps a local history of what DiskWise did, and
            Settings let you tune scanning limits, notifications, menu bar behavior, and AI options
            without creating an account.
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

          <div className="mt-6 rounded-2xl border border-brand-blue/20 bg-brand-blue/10 p-5">
            <p className="flex items-center gap-2 text-sm font-semibold text-brand-blueLight">
              <span aria-hidden>🛡️</span>
              Privacy first
            </p>
            <ul className="mt-3 grid gap-2 sm:grid-cols-2">
              {privacyChecks.map((item) => (
                <li key={item} className="flex items-center gap-2 text-sm text-slate-300">
                  <span className="text-brand-blueLight" aria-hidden>
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
