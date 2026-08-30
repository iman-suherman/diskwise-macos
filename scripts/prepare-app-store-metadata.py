#!/usr/bin/env python3
"""Fill required App Store Connect metadata so DiskWise can be submitted for review."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LISTING = json.loads((ROOT / "app-store-connect" / "listing.json").read_text())
APP_ID = str(LISTING["appleId"])
PRIVACY_URL = LISTING["privacyPolicyUrl"]
ASC_ROOT = ROOT / "app-store-connect" / "asc"


def load_upload():
    path = ROOT / "scripts" / "upload-app-store-listing.py"
    spec = importlib.util.spec_from_file_location("asc_upload", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def ensure_content_rights(client) -> None:
    client.patch(
        f"/v1/apps/{APP_ID}",
        {
            "data": {
                "type": "apps",
                "id": APP_ID,
                "attributes": {
                    "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT",
                },
            }
        },
    )
    print("Set contentRightsDeclaration=DOES_NOT_USE_THIRD_PARTY_CONTENT")


def ensure_category_and_privacy(client) -> None:
    infos = client.get(f"/v1/apps/{APP_ID}/appInfos")["data"]
    if not infos:
        raise SystemExit("No appInfos found")
    info = infos[0]
    info_id = info["id"]

    # Primary category: Utilities
    client.patch(
        f"/v1/appInfos/{info_id}",
        {
            "data": {
                "type": "appInfos",
                "id": info_id,
                "relationships": {
                    "primaryCategory": {
                        "data": {"type": "appCategories", "id": "UTILITIES"}
                    }
                },
            }
        },
    )
    print("Set primaryCategory=UTILITIES")

    locs = client.get(f"/v1/appInfos/{info_id}/appInfoLocalizations")["data"]
    wanted = LISTING.get("primaryLocale", "en-AU")
    for loc in locs:
        locale = loc["attributes"]["locale"]
        if locale != wanted and len(locs) > 1:
            continue
        client.patch(
            f"/v1/appInfoLocalizations/{loc['id']}",
            {
                "data": {
                    "type": "appInfoLocalizations",
                    "id": loc["id"],
                    "attributes": {
                        "privacyPolicyUrl": PRIVACY_URL,
                        "name": "DiskWise",
                        "subtitle": "Photos storage consultant",
                    },
                }
            },
        )
        print(f"Set privacyPolicyUrl + subtitle for {locale}")


def ensure_age_rating(client, version_id: str) -> None:
    decl = client.get(f"/v1/appStoreVersions/{version_id}/ageRatingDeclaration").get("data")
    if not decl:
        raise SystemExit("ageRatingDeclaration missing")

    # All clear for a local Photos utility with no UGC/ads/violence.
    attrs = {
        "alcoholTobaccoOrDrugUseOrReferences": "NONE",
        "contests": "NONE",
        "gambling": False,
        "gamblingSimulated": "NONE",
        "gunsOrOtherWeapons": "NONE",
        "horrorOrFearThemes": "NONE",
        "matureOrSuggestiveThemes": "NONE",
        "medicalOrTreatmentInformation": "NONE",
        "profanityOrCrudeHumor": "NONE",
        "sexualContentGraphicAndNudity": "NONE",
        "sexualContentOrNudity": "NONE",
        "unrestrictedWebAccess": False,
        "violenceCartoonOrFantasy": "NONE",
        "violenceRealistic": "NONE",
        "violenceRealisticProlongedGraphicOrSadistic": "NONE",
        "lootBox": False,
        "advertising": False,
        "ageAssurance": False,
        "healthOrWellnessTopics": False,
        "messagingAndChat": False,
        "parentalControls": False,
        "userGeneratedContent": False,
    }
    client.patch(
        f"/v1/ageRatingDeclarations/{decl['id']}",
        {
            "data": {
                "type": "ageRatingDeclarations",
                "id": decl["id"],
                "attributes": attrs,
            }
        },
    )
    print("Set age rating declaration (all clear / NONE)")


def ensure_ipad_3gen_screenshots(client, upload) -> None:
    version = upload.find_version(client)
    locs = upload.ensure_localizations(client, version["id"])
    files = sorted((ASC_ROOT / "ipad-13").glob("*.png"))
    if not files:
        print("Skip APP_IPAD_PRO_3GEN_129 — no ipad screenshots on disk")
        return
    for locale, loc_id in locs.items():
        set_id = upload.ensure_set(
            client,
            loc_id,
            "appScreenshotSets",
            "screenshotDisplayType",
            "APP_IPAD_PRO_3GEN_129",
            ["APP_IPAD_PRO_3GEN_129", "APP_IPAD_PRO_129", "APP_IPAD_PRO_2018_129"],
            "appStoreVersionLocalization",
            "appScreenshotSets",
        )
        if not set_id:
            continue
        print(f"Uploading APP_IPAD_PRO_3GEN_129 screenshots for {locale}…")
        upload.replace_screenshots(client, set_id, files)


def ensure_privacy_nutrition(client) -> None:
    """Declare that the app does not collect data, then publish."""
    # Prefer DATA_NOT_COLLECTED if available for this API version.
    existing = client.get(
        f"/v1/apps/{APP_ID}/appDataUsages",
        params={"limit": 50},
    ).get("data") or []
    if existing:
        print(f"App data usages already present ({len(existing)}); attempting publish…")
    else:
        try:
            client.post(
                "/v1/appDataUsages",
                {
                    "data": {
                        "type": "appDataUsages",
                        "relationships": {
                            "app": {"data": {"type": "apps", "id": APP_ID}},
                            "category": {
                                "data": {
                                    "type": "appDataUsageCategories",
                                    "id": "DATA_NOT_COLLECTED",
                                }
                            },
                        },
                    }
                },
            )
            print("Created DATA_NOT_COLLECTED usage declaration")
        except SystemExit as exc:
            print(f"DATA_NOT_COLLECTED create note: {exc}")

    # Publish privacy answers when the endpoint is available.
    try:
        states = client.get(
            f"/v1/apps/{APP_ID}/appDataUsagePublishState"
        ).get("data")
        if states:
            state_id = states["id"] if isinstance(states, dict) else states[0]["id"]
            client.patch(
                f"/v1/appDataUsagePublishStates/{state_id}",
                {
                    "data": {
                        "type": "appDataUsagePublishStates",
                        "id": state_id,
                        "attributes": {"published": True},
                    }
                },
            )
            print("Published app privacy nutrition answers")
        else:
            print("No appDataUsagePublishState returned — set Privacy in ASC UI if submit still fails")
    except SystemExit as exc:
        print(f"Privacy publish note: {exc}")


def main() -> None:
    upload = load_upload()
    client = upload.Client()
    version = upload.find_version(client)
    version_id = version["id"]
    print(
        f"Preparing metadata for version {version['attributes']['versionString']} ({version_id})"
    )
    ensure_content_rights(client)
    ensure_category_and_privacy(client)
    ensure_age_rating(client, version_id)
    ensure_ipad_3gen_screenshots(client, upload)
    ensure_privacy_nutrition(client)
    print("Metadata prepare complete.")


if __name__ == "__main__":
    main()
