import type { Metadata } from "next";
import Link from "next/link";
import { BRAND_NAME, SITE_URL } from "@/lib/brand";

export const metadata: Metadata = {
  title: `Privacy Policy · ${BRAND_NAME}`,
  description: `Privacy policy for ${BRAND_NAME} on Mac, iPhone, iPad, and Android.`,
  alternates: { canonical: `${SITE_URL}/privacy` },
};

export default function PrivacyPage() {
  return (
    <div className="mx-auto max-w-3xl px-4 pb-20 pt-28 sm:px-6 sm:pt-32">
      <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">Legal</p>
      <h1 className="mt-3 text-3xl font-bold tracking-tight text-slate-50 sm:text-4xl">
        Privacy Policy
      </h1>
      <p className="mt-2 text-sm text-slate-500">Last updated: 23 September 2026</p>

      <div className="mt-10 space-y-8 text-sm leading-7 text-slate-300 sm:text-base">
        <section className="space-y-3">
          <h2 className="text-lg font-semibold text-slate-50">Who we are</h2>
          <p>
            {BRAND_NAME} is operated by Iman Suherman (&quot;we&quot;, &quot;us&quot;). It is a
            storage and Photos / gallery consultant available for macOS, iPhone, iPad, and Android.
            Contact:{" "}
            <a className="text-brand-blue hover:text-brand-blueLight" href="mailto:iman.suherman@gmail.com">
              iman.suherman@gmail.com
            </a>{" "}
            ·{" "}
            <a className="text-brand-blue hover:text-brand-blueLight" href={SITE_URL}>
              {SITE_URL}
            </a>
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-lg font-semibold text-slate-50">Summary</h2>
          <p>
            DiskWise analyzes storage and media <strong className="font-semibold text-slate-100">on your device</strong>.
            File paths, photo and video contents, thumbnails, and cleanup selections are not uploaded to our servers.
            There is no DiskWise account and no cloud sync of your media as part of the product.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-lg font-semibold text-slate-50">Data processed on your device</h2>
          <p>Depending on the platform, DiskWise may read locally:</p>
          <ul className="list-disc space-y-2 pl-5 text-slate-400">
            <li>
              <strong className="font-medium text-slate-200">macOS</strong> — volume and folder metadata,
              file sizes and types, system health metrics, and optional local AI insights you enable.
            </li>
            <li>
              <strong className="font-medium text-slate-200">iPhone &amp; iPad</strong> — Photos library
              metadata and assets you grant access to, for duplicates, clutter buckets, and cleanup
              recommendations.
            </li>
            <li>
              <strong className="font-medium text-slate-200">Android</strong> — gallery images and videos
              via MediaStore (and legacy storage permission on older Android versions) to scan,
              estimate reclaimable space, and move selected items to system Trash after you confirm.
            </li>
          </ul>
          <p>
            Cleanup defaults to recoverable Trash / Recently Deleted workflows. DiskWise does not empty
            system Trash for you in the current Android release.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-lg font-semibold text-slate-50">Permissions</h2>
          <p>
            Permissions (Full Disk Access on Mac, Photos on iOS, Photos and videos on Android) are
            requested only so DiskWise can scan and clean up media you choose. We do not use those
            permissions to collect or transmit your media off-device.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-lg font-semibold text-slate-50">Data we do not collect</h2>
          <ul className="list-disc space-y-2 pl-5 text-slate-400">
            <li>No account registration or sign-in</li>
            <li>No advertising ID collection for ads (DiskWise does not show ads)</li>
            <li>No sale of personal data</li>
            <li>No upload of photo/video contents or file paths to DiskWise servers</li>
          </ul>
        </section>

        <section className="space-y-3">
          <h2 className="text-lg font-semibold text-slate-50">This website</h2>
          <p>
            The marketing site at {SITE_URL} provides product information, downloads, and this policy.
            It may use standard web analytics (for example Google Analytics) to understand aggregate
            traffic. The website does not access your device storage or photo library.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-lg font-semibold text-slate-50">Optional on-device AI (Mac)</h2>
          <p>
            On Mac, Apple Intelligence insights and optional local tools such as Ollama or LM Studio
            run on your machine when you enable them. Those features do not send your files to a
            DiskWise cloud service.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-lg font-semibold text-slate-50">Children</h2>
          <p>
            DiskWise is not directed at children under 13. We do not knowingly collect personal
            information from children.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-lg font-semibold text-slate-50">Changes</h2>
          <p>
            We may update this policy when the product changes. The &quot;Last updated&quot; date at
            the top will change when we do. Continued use of DiskWise after an update means you
            accept the revised policy.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-lg font-semibold text-slate-50">Contact</h2>
          <p>
            Privacy questions:{" "}
            <a className="text-brand-blue hover:text-brand-blueLight" href="mailto:iman.suherman@gmail.com">
              iman.suherman@gmail.com
            </a>
          </p>
        </section>
      </div>

      <Link
        href="/"
        className="mt-12 inline-flex text-sm font-semibold text-brand-blue transition hover:text-brand-blueLight"
      >
        ← Back to {BRAND_NAME}
      </Link>
    </div>
  );
}
