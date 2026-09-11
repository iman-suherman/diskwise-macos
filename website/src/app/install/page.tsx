import type { Metadata } from "next";
import { InstallGuide } from "@/components/InstallGuide";
import { BRAND_NAME } from "@/lib/brand";

export const metadata: Metadata = {
  title: `Download · ${BRAND_NAME}`,
  description:
    "Download DiskWise for Mac as a notarized DMG, or get DiskWise for iPhone and iPad on the App Store.",
};

export default function InstallPage() {
  return <InstallGuide />;
}
