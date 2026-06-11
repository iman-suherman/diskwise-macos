import { CtaBanner } from "@/components/CtaBanner";
import { AppPreview } from "@/components/AppPreview";
import { FeatureShowcase } from "@/components/FeatureShowcase";
import { Hero } from "@/components/Hero";
import { OpenSourceSection } from "@/components/OpenSourceSection";
import { PrivacySection } from "@/components/PrivacySection";
import { VersionHistoryShowcase } from "@/components/VersionHistoryShowcase";

export default function HomePage() {
  return (
    <>
      <Hero />
      <AppPreview />
      <PrivacySection />
      <FeatureShowcase />
      <VersionHistoryShowcase />
      <OpenSourceSection />
      <CtaBanner />
    </>
  );
}
