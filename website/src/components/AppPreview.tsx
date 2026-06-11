import Image from "next/image";
import { BRAND_NAME } from "@/lib/brand";

export function AppPreview() {
  return (
    <section id="preview" className="mx-auto max-w-7xl px-4 py-6 sm:px-6 sm:py-8 md:py-10">
      <div className="mx-auto max-w-3xl text-center">
        <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
          Native macOS app
        </p>
        <h2 className="mt-2 text-2xl font-bold text-slate-50 sm:text-3xl md:text-4xl">
          Scan drives, track progress, and act on insights from one place.
        </h2>
        <p className="mt-3 text-base leading-7 text-slate-400">
          Browse internal and external volumes, monitor live scan progress, and review capacity,
          distribution, and AI recommendations in a focused SwiftUI workspace.
        </p>
      </div>

      <div className="relative mx-auto mt-8 max-w-6xl">
        <div className="absolute -inset-6 rounded-[2rem] bg-gradient-to-br from-brand-blue/20 via-brand-purple/10 to-transparent blur-3xl" />
        <Image
          src="/app-screenshot.png"
          alt={`${BRAND_NAME} scanning Macintosh HD with storage overview, capacity chart, and AI recommendations`}
          width={2400}
          height={1500}
          className="relative h-auto w-full rounded-2xl shadow-card ring-1 ring-white/10"
          priority={false}
        />
      </div>
    </section>
  );
}
