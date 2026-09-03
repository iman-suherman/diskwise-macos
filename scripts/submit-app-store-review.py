#!/usr/bin/env python3
"""Attach the latest uploaded build and submit DiskWise for App Store review."""
from __future__ import annotations

import importlib.util
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LISTING = json.loads((ROOT / "app-store-connect" / "listing.json").read_text())
APP_ID = str(LISTING["appleId"])
API = "https://api.appstoreconnect.apple.com"
PROJECT_YML = ROOT / "app" / "project.yml"
STATUS_FILE = ROOT / "app-store-connect" / "testflight-status.json"

SUBMITTABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}
BLOCKED_STATES = {
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
    "PENDING_DEVELOPER_RELEASE",
    "READY_FOR_SALE",
    "PROCESSING_FOR_APP_STORE",
}


def load_upload_module():
    path = ROOT / "scripts" / "upload-app-store-listing.py"
    spec = importlib.util.spec_from_file_location("asc_upload", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_build_number() -> str:
    if STATUS_FILE.exists():
        try:
            status = json.loads(STATUS_FILE.read_text())
            if status.get("marketingVersion") == LISTING["versionString"]:
                return str(status["buildNumber"])
        except (json.JSONDecodeError, KeyError, TypeError):
            pass
    text = PROJECT_YML.read_text()
    # Prefer DiskWiseiOS target version in the shared project.yml
    match = re.search(
        r"DiskWiseiOS:[\s\S]*?CURRENT_PROJECT_VERSION:\s*(\S+)",
        text,
    )
    if not match:
        match = re.search(r"CURRENT_PROJECT_VERSION:\s*(\S+)", text)
    if not match:
        raise SystemExit("Could not read CURRENT_PROJECT_VERSION from project.yml")
    return match.group(1)


def ensure_version(client, upload) -> dict:
    versions = client.get(
        f"/v1/apps/{APP_ID}/appStoreVersions",
        params={"filter[platform]": "IOS", "limit": 50},
    )["data"]
    wanted = LISTING["versionString"]
    for item in versions:
        if item["attributes"]["versionString"] == wanted:
            return item

    # Prefer an editable version if ASC created a default (e.g. 1.0) on first app setup.
    editable = {
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "INVALID_BINARY",
    }
    for item in versions:
        state = item["attributes"].get("appStoreState") or item["attributes"].get(
            "appVersionState"
        )
        if state in editable:
            if item["attributes"]["versionString"] != wanted:
                print(
                    f"Updating App Store version string "
                    f"{item['attributes']['versionString']} → {wanted}…"
                )
                client.patch(
                    f"/v1/appStoreVersions/{item['id']}",
                    {
                        "data": {
                            "type": "appStoreVersions",
                            "id": item["id"],
                            "attributes": {"versionString": wanted},
                        }
                    },
                )
                item["attributes"]["versionString"] = wanted
            return item

    print(f"Creating App Store version {wanted}…")
    created = client.post(
        "/v1/appStoreVersions",
        {
            "data": {
                "type": "appStoreVersions",
                "attributes": {
                    "platform": "IOS",
                    "versionString": wanted,
                    "releaseType": LISTING.get("releaseType", "AFTER_APPROVAL"),
                },
                "relationships": {
                    "app": {"data": {"type": "apps", "id": APP_ID}}
                },
            }
        },
    )
    return created["data"]


def find_build(client, build_number: str) -> dict:
    payload = client.get(
        "/v1/builds",
        params={
            "filter[app]": APP_ID,
            "filter[version]": build_number,
            "include": "preReleaseVersion",
            "limit": 20,
            "sort": "-uploadedDate",
        },
    )
    included = {
        item["id"]: item
        for item in payload.get("included", [])
        if item.get("type") == "preReleaseVersions"
    }
    wanted_marketing = LISTING["versionString"]
    for item in payload.get("data", []):
        prerelease_id = (
            item.get("relationships", {})
            .get("preReleaseVersion", {})
            .get("data", {})
            .get("id")
        )
        prerelease = included.get(prerelease_id) if prerelease_id else None
        marketing = (prerelease or {}).get("attributes", {}).get("version")
        processing = item["attributes"].get("processingState")
        if marketing == wanted_marketing:
            if processing and processing != "VALID":
                print(
                    f"Build {build_number} for {wanted_marketing} is {processing}; "
                    "waiting may be required before submission."
                )
            return item
    raise SystemExit(
        f"No build {wanted_marketing} ({build_number}) found in App Store Connect. "
        "Run npm run publish:testflight first and wait for processing to finish."
    )


def attach_build(client, version_id: str, build_id: str) -> None:
    client.patch(
        f"/v1/appStoreVersions/{version_id}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": version_id,
                "relationships": {
                    "build": {"data": {"type": "builds", "id": build_id}}
                },
            }
        },
    )
    print(f"Attached build {build_id} to version {version_id}")


def set_export_compliance(client, build_id: str) -> None:
    try:
        client.patch(
            f"/v1/builds/{build_id}",
            {
                "data": {
                    "type": "builds",
                    "id": build_id,
                    "attributes": {"usesNonExemptEncryption": False},
                }
            },
        )
        print("Set export compliance: usesNonExemptEncryption=false")
    except SystemExit as exc:
        if "409" in str(exc) and "usesNonExemptEncryption" in str(exc):
            print("Export compliance already set on build.")
            return
        raise


def update_review_detail(client, version_id: str) -> None:
    review = LISTING.get("review") or {}
    if not review:
        return

    attributes = {
        "contactFirstName": review["contactFirstName"],
        "contactLastName": review["contactLastName"],
        "contactPhone": review["contactPhone"],
        "contactEmail": review["contactEmail"],
        "demoAccountRequired": review.get("demoAccountRequired", False),
        "notes": review.get("notes", ""),
    }
    if review.get("demoAccountRequired"):
        attributes["demoAccountName"] = review.get("demoAccountName", "")
        attributes["demoAccountPassword"] = review.get("demoAccountPassword", "")

    detail_payload = client.get(
        f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail"
    )
    detail = detail_payload.get("data")
    if detail:
        client.patch(
            f"/v1/appStoreReviewDetails/{detail['id']}",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "id": detail["id"],
                    "attributes": attributes,
                }
            },
        )
    else:
        client.post(
            "/v1/appStoreReviewDetails",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": attributes,
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version_id}
                        }
                    },
                }
            },
        )
    print("Updated App Review contact + notes")


def submit_for_review(client, version_id: str) -> None:
    # Apple replaced appStoreVersionSubmissions with the 3-step reviewSubmissions flow.
    open_submission = client.get(
        f"/v1/apps/{APP_ID}/reviewSubmissions",
        params={"filter[platform]": "IOS", "limit": 10},
    )["data"]

    # Metadata rejections leave a submission in UNRESOLVED_ISSUES that cannot accept
    # more items — cancel it and start a fresh submission.
    reusable_states = {"READY_FOR_REVIEW", "WAITING_FOR_REVIEW"}
    submission_id = None
    for item in open_submission:
        state = item["attributes"].get("state")
        if state in {"COMPLETE", "CANCELLED"}:
            continue
        if state == "UNRESOLVED_ISSUES":
            sid = item["id"]
            print(f"Cancelling unresolved review submission {sid}…")
            client.patch(
                f"/v1/reviewSubmissions/{sid}",
                {
                    "data": {
                        "type": "reviewSubmissions",
                        "id": sid,
                        "attributes": {"canceled": True},
                    }
                },
            )
            # ASC needs a beat before the version can join a new submission.
            import time

            time.sleep(3)
            continue
        if state in reusable_states:
            submission_id = item["id"]
            print(f"Reusing open review submission {submission_id} (state={state}).")
            break
        print(f"Note: leaving review submission {item['id']} (state={state}) alone.")

    if submission_id is None:
        created = client.post(
            "/v1/reviewSubmissions",
            {
                "data": {
                    "type": "reviewSubmissions",
                    "attributes": {"platform": "IOS"},
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": APP_ID}}
                    },
                }
            },
        )
        submission_id = created["data"]["id"]
        print(f"Created review submission {submission_id}.")

    client.post(
        "/v1/reviewSubmissionItems",
        {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {
                        "data": {"type": "reviewSubmissions", "id": submission_id}
                    },
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": version_id}
                    },
                },
            }
        },
    )
    print(f"Added version {version_id} to review submission.")

    client.patch(
        f"/v1/reviewSubmissions/{submission_id}",
        {
            "data": {
                "type": "reviewSubmissions",
                "id": submission_id,
                "attributes": {"submitted": True},
            }
        },
    )
    print("Submitted for App Store review.")


def main() -> None:
    upload = load_upload_module()
    client = upload.Client()
    build_number = os.environ.get("DISKWISE_BUILD_NUMBER") or read_build_number()
    skip_upload = os.environ.get("DISKWISE_SKIP_LISTING_UPLOAD") == "1"

    version = ensure_version(client, upload)
    version_id = version["id"]
    state = version["attributes"].get("appStoreState") or version["attributes"].get(
        "appVersionState"
    )
    print(
        f"Version {version['attributes']['versionString']} "
        f"state={state or 'unknown'} build_target={build_number}"
    )

    if state in BLOCKED_STATES:
        print(f"Version is already {state}; nothing to submit.")
        return
    if state and state not in SUBMITTABLE_STATES:
        print(f"Warning: unexpected version state {state}; attempting submit anyway.")

    if not skip_upload:
        print("Uploading listing metadata + screenshots…")
        upload.main()

    build = find_build(client, build_number)
    set_export_compliance(client, build["id"])
    attach_build(client, version_id, build["id"])
    update_review_detail(client, version_id)
    submit_for_review(client, version_id)

    print(
        "App Store Connect: "
        f"https://appstoreconnect.apple.com/apps/{APP_ID}/distribution/ios/version/inflight"
    )


if __name__ == "__main__":
    try:
        main()
    except SystemExit as exc:
        if exc.code:
            print(exc, file=sys.stderr)
        raise
