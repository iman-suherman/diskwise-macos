import type { Metadata } from "next";
import { InstallGuide } from "@/components/InstallGuide";
import { BRAND_NAME } from "@/lib/brand";

export const metadata: Metadata = {
  title: `Download · ${BRAND_NAME}`,
  description:
    "Download DiskWise for Mac as a notarized DMG, get it on the App Store for iPhone and iPad, or on Google Play for Android.",
};

export default function InstallPage() {
  return <InstallGuide />;
}
