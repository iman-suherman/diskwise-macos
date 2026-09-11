import { APP_STORE_URL, BRAND_NAME } from "@/lib/brand";

type AppStoreLinkProps = {
  variant?: "badge" | "button" | "text";
  className?: string;
};

export function AppStoreLink({ variant = "button", className }: AppStoreLinkProps) {
  const label = `Download ${BRAND_NAME} on the App Store`;

  if (variant === "badge") {
    return (
      <a
        href={APP_STORE_URL}
        target="_blank"
        rel="noopener noreferrer"
        className={["app-store-badge", className].filter(Boolean).join(" ")}
        aria-label={label}
      >
        <img
          src="/badges/download-on-the-app-store.svg"
          alt="Download on the App Store"
          width={120}
          height={40}
        />
      </a>
    );
  }

  if (variant === "text") {
    return (
      <a
        href={APP_STORE_URL}
        target="_blank"
        rel="noopener noreferrer"
        className={className}
      >
        App Store
      </a>
    );
  }

  return (
    <a
      href={APP_STORE_URL}
      target="_blank"
      rel="noopener noreferrer"
      className={className ?? "btn-secondary"}
    >
      Get on the App Store
    </a>
  );
}
