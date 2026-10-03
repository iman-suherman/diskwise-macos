import { BRAND_NAME, PLAY_STORE_URL } from "@/lib/brand";

type GooglePlayLinkProps = {
  variant?: "badge" | "button" | "text";
  className?: string;
};

export function GooglePlayLink({ variant = "button", className }: GooglePlayLinkProps) {
  const label = `Get ${BRAND_NAME} on Google Play`;

  if (variant === "badge") {
    return (
      <a
        href={PLAY_STORE_URL}
        target="_blank"
        rel="noopener noreferrer"
        className={["google-play-badge", className].filter(Boolean).join(" ")}
        aria-label={label}
      >
        <img
          src="/badges/get-it-on-google-play.png"
          alt="Get it on Google Play"
          width={135}
          height={40}
        />
      </a>
    );
  }

  if (variant === "text") {
    return (
      <a
        href={PLAY_STORE_URL}
        target="_blank"
        rel="noopener noreferrer"
        className={className}
      >
        Google Play
      </a>
    );
  }

  return (
    <a
      href={PLAY_STORE_URL}
      target="_blank"
      rel="noopener noreferrer"
      className={className ?? "btn-secondary"}
    >
      Get on Google Play
    </a>
  );
}
