"use client";

import { useEffect, useState } from "react";

type LocalReleaseDateProps = {
  iso: string;
  className?: string;
};

export function LocalReleaseDate({ iso, className }: LocalReleaseDateProps) {
  const [label, setLabel] = useState<string | null>(null);

  useEffect(() => {
    setLabel(
      new Date(iso).toLocaleString(undefined, {
        dateStyle: "medium",
        timeStyle: "short",
      }),
    );
  }, [iso]);

  if (!label) return null;

  return (
    <time dateTime={iso} className={className}>
      Released {label}
    </time>
  );
}
