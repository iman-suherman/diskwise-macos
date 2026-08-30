#!/usr/bin/env python3
"""Upload DiskWise App Store listing, screenshots, and previews via the App Store Connect API."""
from __future__ import annotations

import hashlib
import json
import os
import time
from pathlib import Path

import jwt
import requests

ROOT = Path(__file__).resolve().parents[1]
LISTING = json.loads((ROOT / "app-store-connect" / "listing.json").read_text())
ASC_ROOT = ROOT / "app-store-connect" / "asc"
API = "https://api.appstoreconnect.apple.com"
APP_ID = str(LISTING["appleId"])

DISPLAY_TYPES = {
    "iphone-69": "APP_IPHONE_69",
    "ipad-13": "APP_IPAD_PRO_129",
    "watch-ultra": "APP_WATCH_ULTRA",
}
PREVIEW_TYPES = {
    "iphone-69": "IPHONE_69",
    "ipad-13": "IPAD_PRO_129",
    "watch-ultra": "APPLE_WATCH_ULTRA",
}

# Fallback display types Apple has used across API versions.
DISPLAY_TYPE_FALLBACKS = {
    "APP_IPHONE_69": ["APP_IPHONE_69", "APP_IPHONE_67"],
    "APP_IPAD_PRO_129": ["APP_IPAD_PRO_129", "APP_IPAD_PRO_3GEN_129", "APP_IPAD_PRO_2018_129"],
    "APP_WATCH_ULTRA": ["APP_WATCH_ULTRA", "APP_WATCH_ULTRA_2", "APP_APPLE_WATCH_ULTRA"],
}
PREVIEW_TYPE_FALLBACKS = {
    "IPHONE_69": ["IPHONE_69", "IPHONE_67"],
    "IPAD_PRO_129": ["IPAD_PRO_129", "IPAD_PRO_3GEN_129"],
    "APPLE_WATCH_ULTRA": ["APPLE_WATCH_ULTRA", "APPLE_WATCH_ULTRA_2"],
}


INFRA_ASC = Path(
    os.environ.get(
        "ASC_CREDENTIALS_DIR",
        str(ROOT.parent.parent / "halort" / "halort-infra" / ".credentials" / "asc"),
    )
)


def load_stack_asc_credentials() -> None:
    if os.environ.get("APP_STORE_CONNECT_KEY_ID") or os.environ.get("ASC_KEY_ID"):
        return
    if not INFRA_ASC.is_dir():
        return
    issuer_file = INFRA_ASC / "issuer-id.txt"
    keys = sorted(INFRA_ASC.glob("AuthKey_*.p8"))
    if not issuer_file.exists() or not keys:
        return
    key_path = keys[0]
    os.environ.setdefault("APP_STORE_CONNECT_ISSUER_ID", issuer_file.read_text().strip())
    os.environ.setdefault("APP_STORE_CONNECT_PRIVATE_KEY_PATH", str(key_path))
    os.environ.setdefault("APP_STORE_CONNECT_KEY_ID", key_path.stem.replace("AuthKey_", ""))


def token() -> str:
    load_stack_asc_credentials()
    key_id = os.environ.get("APP_STORE_CONNECT_KEY_ID") or os.environ.get("ASC_KEY_ID")
    issuer = os.environ.get("APP_STORE_CONNECT_ISSUER_ID") or os.environ.get("ASC_ISSUER_ID")
    key_path = (
        os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY_PATH")
        or os.environ.get("ASC_PRIVATE_KEY_PATH")
    )
    key_pem = os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY") or os.environ.get("ASC_PRIVATE_KEY")
    if not key_pem and key_path:
        key_pem = Path(key_path).expanduser().read_text()
    if not key_id or not key_pem:
        raise SystemExit(
            "Missing App Store Connect API key. Set APP_STORE_CONNECT_KEY_ID and "
            "APP_STORE_CONNECT_PRIVATE_KEY_PATH. Team keys also need APP_STORE_CONNECT_ISSUER_ID."
        )
    now = int(time.time())
    if issuer:
        payload = {
            "iss": issuer,
            "iat": now,
            "exp": now + 19 * 60,
            "aud": "appstoreconnect-v1",
        }
    else:
        # Individual API keys (Users and Access → Integrations) omit issuer.
        payload = {
            "sub": "user",
            "iat": now,
            "exp": now + 19 * 60,
            "aud": "appstoreconnect-v1",
        }
    return jwt.encode(
        payload,
        key_pem,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


class Client:
    def __init__(self) -> None:
        self.session = requests.Session()
        self.session.headers.update(
            {
                "Authorization": f"Bearer {token()}",
                "Content-Type": "application/json",
            }
        )

    def get(self, path: str, params: dict | None = None) -> dict:
        response = self.session.get(f"{API}{path}", params=params, timeout=60)
        if response.status_code >= 400:
            raise SystemExit(f"GET {path} {response.status_code}: {response.text}")
        return response.json()

    def post(self, path: str, body: dict) -> dict:
        response = self.session.post(f"{API}{path}", json=body, timeout=60)
        if response.status_code >= 400:
            raise SystemExit(f"POST {path} {response.status_code}: {response.text}")
        return response.json() if response.text else {}

    def patch(self, path: str, body: dict) -> dict:
        response = self.session.patch(f"{API}{path}", json=body, timeout=60)
        if response.status_code >= 400:
            raise SystemExit(f"PATCH {path} {response.status_code}: {response.text}")
        return response.json() if response.text else {}

    def delete(self, path: str) -> None:
        response = self.session.delete(f"{API}{path}", timeout=60)
        if response.status_code not in (200, 204):
            raise SystemExit(f"DELETE {path} {response.status_code}: {response.text}")


def find_version(client: Client) -> dict:
    data = client.get(
        f"/v1/apps/{APP_ID}/appStoreVersions",
        params={"filter[platform]": "IOS", "limit": 20},
    )["data"]
    wanted = LISTING["versionString"]
    editable = {
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "WAITING_FOR_REVIEW",
    }
    for item in data:
        if item["attributes"]["versionString"] == wanted:
            return item
    for item in data:
        if item["attributes"]["appStoreState"] in editable or item["attributes"].get(
            "appVersionState"
        ) in {
            "PREPARE_FOR_SUBMISSION",
            "DEVELOPER_REJECTED",
            "REJECTED",
            "METADATA_REJECTED",
        }:
            return item
    if data:
        return data[0]
    raise SystemExit("No iOS App Store version found")


def ensure_localizations(client: Client, version_id: str) -> dict[str, str]:
    existing = client.get(
        f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations"
    )["data"]
    by_locale = {item["attributes"]["locale"]: item["id"] for item in existing}
    for locale in LISTING["locales"]:
        if locale in by_locale:
            continue
        created = client.post(
            "/v1/appStoreVersionLocalizations",
            {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "attributes": {"locale": locale},
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version_id}
                        }
                    },
                }
            },
        )
        by_locale[locale] = created["data"]["id"]
    return by_locale


def update_metadata(client: Client, version: dict, localizations: dict[str, str]) -> None:
    client.patch(
        f"/v1/appStoreVersions/{version['id']}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": version["id"],
                "attributes": {
                    "versionString": LISTING["versionString"],
                    "copyright": LISTING["copyright"],
                },
            }
        },
    )
    for locale, payload in LISTING["locales"].items():
        loc_id = localizations[locale]
        attrs = {
            "description": payload["description"],
            "keywords": payload["keywords"],
            "promotionalText": payload["promotionalText"],
            "supportUrl": LISTING["supportUrl"],
            "marketingUrl": LISTING["marketingUrl"],
        }
        # First App Store version rejects whatsNew.
        if payload.get("whatsNew"):
            attrs["whatsNew"] = payload["whatsNew"]
        client.patch(
            f"/v1/appStoreVersionLocalizations/{loc_id}",
            {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": loc_id,
                    "attributes": attrs,
                }
            },
        )
        print(f"Updated listing copy for {locale}")


def upload_file(client: Client, operations: list[dict], path: Path) -> None:
    data = path.read_bytes()
    offset = 0
    for op in operations:
        length = int(op["length"])
        chunk = data[offset : offset + length]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
        response = requests.request(
            op["method"],
            op["url"],
            data=chunk,
            headers=headers,
            timeout=300,
        )
        if response.status_code >= 400:
            raise SystemExit(f"Asset upload failed {response.status_code}: {response.text}")
        offset += length


def md5(path: Path) -> str:
    return hashlib.md5(path.read_bytes()).hexdigest()


def ensure_set(
    client: Client,
    loc_id: str,
    kind: str,
    type_attr: str,
    type_value: str,
    fallbacks: list[str],
    relationship: str,
    set_type: str,
) -> str | None:
    listed = client.get(
        f"/v1/appStoreVersionLocalizations/{loc_id}/{kind}"
    )["data"]
    existing = {item["attributes"][type_attr]: item["id"] for item in listed}
    for candidate in fallbacks:
        if candidate in existing:
            return existing[candidate]
    last_error = None
    for candidate in fallbacks:
        try:
            created = client.post(
                f"/v1/{kind}",
                {
                    "data": {
                        "type": set_type,
                        "attributes": {type_attr: candidate},
                        "relationships": {
                            relationship: {
                                "data": {
                                    "type": "appStoreVersionLocalizations",
                                    "id": loc_id,
                                }
                            }
                        },
                    }
                },
            )
            print(f"Created {kind} {candidate}")
            return created["data"]["id"]
        except SystemExit as error:
            last_error = error
            continue
    print(f"Skip {kind} {type_value}: {last_error}")
    return None


def replace_screenshots(client: Client, set_id: str, files: list[Path]) -> None:
    existing = client.get(f"/v1/appScreenshotSets/{set_id}/appScreenshots")["data"]
    for item in existing:
        client.delete(f"/v1/appScreenshots/{item['id']}")
    for index, path in enumerate(files):
        reserved = client.post(
            "/v1/appScreenshots",
            {
                "data": {
                    "type": "appScreenshots",
                    "attributes": {
                        "fileName": path.name,
                        "fileSize": path.stat().st_size,
                    },
                    "relationships": {
                        "appScreenshotSet": {
                            "data": {"type": "appScreenshotSets", "id": set_id}
                        }
                    },
                }
            },
        )["data"]
        upload_file(client, reserved["attributes"]["uploadOperations"], path)
        client.patch(
            f"/v1/appScreenshots/{reserved['id']}",
            {
                "data": {
                    "type": "appScreenshots",
                    "id": reserved["id"],
                    "attributes": {
                        "uploaded": True,
                        "sourceFileChecksum": md5(path),
                    },
                }
            },
        )
        print(f"  screenshot {index + 1}/{len(files)} {path.name}")


def clear_previews(client: Client, set_id: str, label: str) -> None:
    existing = client.get(f"/v1/appPreviewSets/{set_id}/appPreviews")["data"]
    if not existing:
        return
    for item in existing:
        client.delete(f"/v1/appPreviews/{item['id']}")
        print(f"  cleared preview {item['id']} ({label})")


def replace_previews(client: Client, set_id: str, files: list[Path]) -> None:
    existing = client.get(f"/v1/appPreviewSets/{set_id}/appPreviews")["data"]
    for item in existing:
        client.delete(f"/v1/appPreviews/{item['id']}")
    for index, path in enumerate(files[:3]):
        reserved = client.post(
            "/v1/appPreviews",
            {
                "data": {
                    "type": "appPreviews",
                    "attributes": {
                        "fileName": path.name,
                        "fileSize": path.stat().st_size,
                    },
                    "relationships": {
                        "appPreviewSet": {
                            "data": {"type": "appPreviewSets", "id": set_id}
                        }
                    },
                }
            },
        )["data"]
        upload_file(client, reserved["attributes"]["uploadOperations"], path)
        client.patch(
            f"/v1/appPreviews/{reserved['id']}",
            {
                "data": {
                    "type": "appPreviews",
                    "id": reserved["id"],
                    "attributes": {
                        "uploaded": True,
                        "sourceFileChecksum": md5(path),
                    },
                }
            },
        )
        print(f"  preview {index + 1}/{len(files)} {path.name}")


def ordered_pngs(folder: Path, preferred: list[str] | None = None) -> list[Path]:
    names = preferred or [
        "login", "beranda", "iuran", "berita", "layanan", "surat", "profil",
    ]
    found = []
    for name in names:
        path = folder / f"{name}.png"
        if path.exists():
            found.append(path)
    for extra in sorted(folder.glob("*.png")):
        if extra not in found:
            found.append(extra)
    return found


def main() -> None:
    client = Client()
    version = find_version(client)
    print(
        f"Version {version['attributes']['versionString']} "
        f"state={version['attributes'].get('appStoreState') or version['attributes'].get('appVersionState')}"
    )
    localizations = ensure_localizations(client, version["id"])
    update_metadata(client, version, localizations)

    # Screenshots for every localization — Apple does not share sets across locales.
    shot_order = (LISTING.get("screenshots") or {}).get("iphone-69") or [
        "onboarding",
        "panduan",
        "tujuan",
        "daftar",
        "privasi",
    ]
    shot_stems = [name.replace(".png", "") for name in shot_order]
    screenshot_map = {
        "iphone-69": ordered_pngs(ASC_ROOT / "iphone-69", shot_stems),
        "ipad-13": ordered_pngs(ASC_ROOT / "ipad-13", shot_stems),
        "watch-ultra": [],
    }
    preview_map = {
        "iphone-69": [],
        "ipad-13": [],
        "watch-ultra": [],
    }

    for locale_code, loc_id in localizations.items():
        for key, files in screenshot_map.items():
            files = [p for p in files if p.exists()]
            if not files:
                continue
            if key == "watch-ultra" and os.environ.get("HALORT_SKIP_WATCH") == "1":
                print("Skip Watch screenshots because HALORT_SKIP_WATCH=1.")
                continue
            type_value = DISPLAY_TYPES[key]
            set_id = ensure_set(
                client,
                loc_id,
                "appScreenshotSets",
                "screenshotDisplayType",
                type_value,
                DISPLAY_TYPE_FALLBACKS[type_value],
                "appStoreVersionLocalization",
                "appScreenshotSets",
            )
            if not set_id:
                continue
            print(f"Uploading screenshots {locale_code}/{key}...")
            replace_screenshots(client, set_id, files)

        for key, files in preview_map.items():
            files = [p for p in files if p.exists()]
            if not files:
                continue
            if os.environ.get("HALORT_SKIP_PREVIEWS") == "1":
                type_value = PREVIEW_TYPES[key]
                set_id = ensure_set(
                    client,
                    loc_id,
                    "appPreviewSets",
                    "previewType",
                    type_value,
                    PREVIEW_TYPE_FALLBACKS[type_value],
                    "appStoreVersionLocalization",
                    "appPreviewSets",
                )
                if set_id:
                    print(f"Clearing previews {locale_code}/{key} (HALORT_SKIP_PREVIEWS=1)…")
                    clear_previews(client, set_id, key)
                else:
                    print(f"Skip previews {locale_code}/{key} because HALORT_SKIP_PREVIEWS=1.")
                continue
            if key == "watch-ultra" and os.environ.get("HALORT_SKIP_WATCH") == "1":
                print("Skip Watch preview because HALORT_SKIP_WATCH=1.")
                continue
            type_value = PREVIEW_TYPES[key]
            set_id = ensure_set(
                client,
                loc_id,
                "appPreviewSets",
                "previewType",
                type_value,
                PREVIEW_TYPE_FALLBACKS[type_value],
                "appStoreVersionLocalization",
                "appPreviewSets",
            )
            if not set_id:
                continue
            print(f"Uploading preview {locale_code}/{key}…")
            replace_previews(client, set_id, files)

    print("App Store Connect listing updated.")
    print(
        f"https://appstoreconnect.apple.com/apps/{APP_ID}/distribution/ios/version/inflight"
    )


if __name__ == "__main__":
    main()
