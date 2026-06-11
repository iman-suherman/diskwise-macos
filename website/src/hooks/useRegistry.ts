"use client";

import { useEffect, useState } from "react";
import {
  APP_ID,
  REGISTRY_API_URL,
  type AppVersion,
  type VersionsResponse,
} from "@/lib/registry";

type FetchState<T> = {
  data: T;
  loading: boolean;
  error: boolean;
};

async function fetchLatestFromRegistry(): Promise<AppVersion | null> {
  const res = await fetch(
    `${REGISTRY_API_URL}/api/v1/plugins/${APP_ID}/versions/latest`,
    { cache: "no-store" },
  );
  if (!res.ok) return null;
  return (await res.json()) as AppVersion;
}

async function fetchAllFromRegistry(): Promise<AppVersion[]> {
  const res = await fetch(
    `${REGISTRY_API_URL}/api/v1/plugins/${APP_ID}/versions`,
    { cache: "no-store" },
  );
  if (!res.ok) return [];
  const data = (await res.json()) as VersionsResponse;
  return data.versions ?? [];
}

export function useLatestVersion(): FetchState<AppVersion | null> {
  const [state, setState] = useState<FetchState<AppVersion | null>>({
    data: null,
    loading: true,
    error: false,
  });

  useEffect(() => {
    let cancelled = false;

    fetchLatestFromRegistry()
      .then((data) => {
        if (!cancelled) {
          setState({ data, loading: false, error: false });
        }
      })
      .catch(() => {
        if (!cancelled) {
          setState({ data: null, loading: false, error: true });
        }
      });

    return () => {
      cancelled = true;
    };
  }, []);

  return state;
}

export function useAllVersions(): FetchState<AppVersion[]> {
  const [state, setState] = useState<FetchState<AppVersion[]>>({
    data: [],
    loading: true,
    error: false,
  });

  useEffect(() => {
    let cancelled = false;

    fetchAllFromRegistry()
      .then((data) => {
        if (!cancelled) {
          setState({ data, loading: false, error: false });
        }
      })
      .catch(() => {
        if (!cancelled) {
          setState({ data: [], loading: false, error: true });
        }
      });

    return () => {
      cancelled = true;
    };
  }, []);

  return state;
}
