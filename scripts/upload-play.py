#!/usr/bin/env python3
"""Upload a signed AAB to Google Play and record status.

Track comes from play-console/listing.json (production by default for review).
Draft apps only accept status=draft on non-internal tracks; after the first
approved release, production can use status=completed.

Called by scripts/publish-play.sh after bundleRelease.
Credentials: ~/src/halort/halort-infra/.credentials/play/service-account.json
(or PLAY_CREDENTIALS_JSON / PLAY_CREDENTIALS_DIR).
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaFileUpload

ROOT = Path(__file__).resolve().parents[1]
LISTING_PATH = ROOT / "play-console" / "listing.json"
STATUS_PATH = ROOT / "play-console" / "play-status.json"
SCOPE = ["https://www.googleapis.com/auth/androidpublisher"]
DEFAULT_CRED_DIR = Path.home() / "src/halort/halort-infra/.credentials/play"


def credentials_path() -> Path:
    env = os.environ.get("PLAY_CREDENTIALS_JSON")
    if env:
        return Path(env).expanduser()
    cred_dir = Path(
        os.environ.get("PLAY_CREDENTIALS_DIR", str(DEFAULT_CRED_DIR))
    ).expanduser()
    candidate = cred_dir / "service-account.json"
    if candidate.is_file():
        return candidate
    jsons = sorted(cred_dir.glob("*.json"))
    if jsons:
        return jsons[0]
    raise SystemExit(
        f"error: Play service account JSON not found.\n"
        f"  Expected: {DEFAULT_CRED_DIR / 'service-account.json'}\n"
        f"  Or set PLAY_CREDENTIALS_JSON / PLAY_CREDENTIALS_DIR"
    )


def publisher():
    path = credentials_path()
    creds = service_account.Credentials.from_service_account_file(
        str(path), scopes=SCOPE
    )
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: upload-play.py <path-to.aab>", file=sys.stderr)
        return 2

    aab = Path(sys.argv[1]).expanduser().resolve()
    if not aab.is_file():
        print(f"error: AAB not found: {aab}", file=sys.stderr)
        return 1

    listing = json.loads(LISTING_PATH.read_text())
    package_name = listing["packageName"]
    track = listing.get("track", "internal")
    version_name = os.environ.get("PLAY_VERSION_NAME", "")
    version_code_env = os.environ.get("PLAY_VERSION_CODE", "")
    git_commit = os.environ.get("PLAY_GIT_COMMIT", "unknown")

    service = publisher()
    try:
        edit = service.edits().insert(packageName=package_name, body={}).execute()
        edit_id = edit["id"]
        print(f"Created edit {edit_id}")

        media = MediaFileUpload(str(aab), mimetype="application/octet-stream", resumable=True)
        bundle = (
            service.edits()
            .bundles()
            .upload(packageName=package_name, editId=edit_id, media_body=media)
            .execute()
        )
        version_code = str(bundle["versionCode"])
        print(f"Uploaded AAB versionCode={version_code}")

        release_notes = []
        for lang, loc in listing.get("locales", {}).items():
            notes = (loc.get("releaseNotes") or "").strip()
            if notes:
                release_notes.append({"language": lang, "text": notes[:500]})

        release_name = version_name or version_code
        # Internal can always complete. Other tracks: PLAY_RELEASE_STATUS or draft
        # (required while the Play app itself is still in draft / first review).
        release_status = os.environ.get("PLAY_RELEASE_STATUS")
        if not release_status:
            release_status = "completed" if track == "internal" else "draft"
        track_body = {
            "track": track,
            "releases": [
                {
                    "name": release_name,
                    "versionCodes": [version_code],
                    "status": release_status,
                    "releaseNotes": release_notes,
                }
            ],
        }
        service.edits().tracks().update(
            packageName=package_name,
            editId=edit_id,
            track=track,
            body=track_body,
        ).execute()
        print(f"Assigned versionCode {version_code} to track={track}")

        icon = ROOT / "play-console" / "icon-512.png"
        if icon.is_file():
            icon_media = MediaFileUpload(str(icon), mimetype="image/png")
            for lang, loc in listing.get("locales", {}).items():
                listing_body = {
                    "language": lang,
                    "title": loc.get("title") or "HaloRT",
                    "shortDescription": loc.get("shortDescription") or "",
                    "fullDescription": loc.get("fullDescription") or "",
                }
                service.edits().listings().update(
                    packageName=package_name,
                    editId=edit_id,
                    language=lang,
                    body=listing_body,
                ).execute()
                uploaded = (
                    service.edits()
                    .images()
                    .upload(
                        packageName=package_name,
                        editId=edit_id,
                        language=lang,
                        imageType="icon",
                        media_body=icon_media,
                    )
                    .execute()
                )
                print(f"Uploaded icon for {lang}: {uploaded}")

        feature = ROOT / "play-console" / "feature-1024x500.png"
        if feature.is_file():
            feature_media = MediaFileUpload(str(feature), mimetype="image/png")
            for lang in listing.get("locales", {}):
                uploaded = (
                    service.edits()
                    .images()
                    .upload(
                        packageName=package_name,
                        editId=edit_id,
                        language=lang,
                        imageType="featureGraphic",
                        media_body=feature_media,
                    )
                    .execute()
                )
                print(f"Uploaded feature graphic for {lang}: {uploaded}")

        screenshots_dir = ROOT / "play-console" / "screenshots"
        if screenshots_dir.is_dir():
            shots = sorted(
                p
                for p in screenshots_dir.iterdir()
                if p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}
            )
            for lang in listing.get("locales", {}):
                for shot in shots[:8]:
                    shot_media = MediaFileUpload(str(shot), mimetype="image/png")
                    uploaded = (
                        service.edits()
                        .images()
                        .upload(
                            packageName=package_name,
                            editId=edit_id,
                            language=lang,
                            imageType="phoneScreenshots",
                            media_body=shot_media,
                        )
                        .execute()
                    )
                    print(f"Uploaded phone screenshot {shot.name} for {lang}: {uploaded}")

        service.edits().commit(packageName=package_name, editId=edit_id).execute()
        print(f"Committed edit {edit_id}")
    except HttpError as exc:
        print(f"error: Play API failed: {exc}", file=sys.stderr)
        if exc.resp is not None and exc.resp.status == 403:
            print(
                "Hint: invite the service account in Play Console → Users and permissions:\n"
                "  dokter-alami-play@personal-suherman.iam.gserviceaccount.com\n"
                "Grant Admin (or Release apps) on HaloRT (id.halort.mobile). "
                "Link Cloud project personal-suherman under Setup → API access if asked.",
                file=sys.stderr,
            )
        elif exc.resp is not None and exc.resp.status == 404:
            print(
                "Hint: create the app in Play Console first with package id.halort.mobile,\n"
                "enroll Play App Signing, then re-run publish-play.sh.",
                file=sys.stderr,
            )
        elif exc.resp is not None and exc.resp.status == 400:
            print(
                "Hint: first upload needs the app created in Play Console, "
                "Play App Signing enrolled, and store presence forms "
                "(Data safety, Content rating, privacy policy, countries).",
                file=sys.stderr,
            )
        return 1

    status = {
        "packageName": package_name,
        "versionName": version_name or None,
        "versionCode": int(version_code_env) if version_code_env.isdigit() else int(version_code),
        "gitCommit": git_commit,
        "uploadedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "track": track,
        "releaseStatus": release_status,
        "note": "Written by scripts/upload-play.py after a successful AAB upload.",
    }
    STATUS_PATH.write_text(json.dumps(status, indent=2) + "\n")
    print(f"Recorded status in {STATUS_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
