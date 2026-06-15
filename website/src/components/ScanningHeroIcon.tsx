import Image from "next/image";
import { BRAND_NAME } from "@/lib/brand";

type ScanningHeroIconProps = {
  className?: string;
  priority?: boolean;
};

export function ScanningHeroIcon({ className = "", priority = false }: ScanningHeroIconProps) {
  return (
    <div className={`scanning-hero ${className}`.trim()}>
      <div aria-hidden className="scanning-hero-glow" />
      <div aria-hidden className="scanning-hero-ring" />
      <div aria-hidden className="scanning-hero-sweep" />
      <Image
        src="/hero-logo.png"
        alt={`${BRAND_NAME} logo`}
        width={1024}
        height={1024}
        priority={priority}
        unoptimized
        sizes="(max-width: 1024px) 90vw, 32rem"
        className="scanning-hero-image relative z-10 h-auto w-full object-contain drop-shadow-[0_16px_40px_rgba(37,89,180,0.35)]"
      />
    </div>
  );
}
