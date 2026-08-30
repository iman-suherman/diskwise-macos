#!/usr/bin/env python3
"""Set DiskWise App Store price to Free (USA base territory)."""
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_ID = "6806657352"


def load_client():
    path = ROOT / "scripts" / "upload-app-store-listing.py"
    spec = importlib.util.spec_from_file_location("asc_upload", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.Client()


def main() -> None:
    client = load_client()
    points = client.get(
        f"/v1/apps/{APP_ID}/appPricePoints",
        params={"filter[territory]": "USA", "limit": 200},
    )["data"]
    free = None
    for point in points:
        price = str(point["attributes"].get("customerPrice", ""))
        try:
            if float(price) == 0.0:
                free = point
                break
        except ValueError:
            continue
    if free is None:
        raise SystemExit("No free (0.0) USA price point found")

    client.post(
        "/v1/appPriceSchedules",
        {
            "data": {
                "type": "appPriceSchedules",
                "relationships": {
                    "app": {"data": {"type": "apps", "id": APP_ID}},
                    "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                    "manualPrices": {
                        "data": [{"type": "appPrices", "id": "${price0}"}]
                    },
                },
            },
            "included": [
                {
                    "type": "appPrices",
                    "id": "${price0}",
                    "attributes": {"startDate": None, "endDate": None},
                    "relationships": {
                        "appPricePoint": {
                            "data": {
                                "type": "appPricePoints",
                                "id": free["id"],
                            }
                        }
                    },
                }
            ],
        },
    )
    print(f"Pricing set to Free (USA base) for app {APP_ID}")


if __name__ == "__main__":
    main()
