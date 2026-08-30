#!/usr/bin/env bash
# Create App Store Connect app + Developer Portal bundle ID for DiskWise iOS.
# Same ASC API key as ArahBaik/HaloRT: halort-infra/.credentials/asc
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HALORT_INFRA="${HALORT_INFRA_ROOT:-$ROOT/../../halort/halort-infra}"
ASC_DIR="${ASC_CREDENTIALS_DIR:-$HALORT_INFRA/.credentials/asc}"
BUNDLE_ID="${BUNDLE_ID:-net.suherman.diskwise.ios}"
APP_NAME="${APP_NAME:-DiskWise}"
SKU="${SKU:-diskwise-ios}"
PRIMARY_LOCALE="${PRIMARY_LOCALE:-en-US}"

if [[ ! -d "$ASC_DIR" ]]; then
  echo "error: ASC credentials directory not found: $ASC_DIR"
  exit 1
fi

PY="${ASC_PYTHON:-}"
if [[ -z "$PY" ]]; then
  if [[ -x "$ROOT/../../halort/halort-mobile-ios/app-store/.venv/bin/python" ]]; then
    PY="$ROOT/../../halort/halort-mobile-ios/app-store/.venv/bin/python"
  else
    echo "error: set ASC_PYTHON to a venv with PyJWT+cryptography"
    exit 1
  fi
fi

"$PY" - "$ASC_DIR" "$BUNDLE_ID" "$APP_NAME" "$SKU" "$PRIMARY_LOCALE" <<'PY'
import json, sys, time, urllib.error, urllib.request
from pathlib import Path
import jwt

asc_dir, bundle_id, app_name, sku, locale = sys.argv[1:]
asc = Path(asc_dir)
issuer = (asc / "issuer-id.txt").read_text().strip()
key_path = next(asc.glob("AuthKey_*.p8"))
key_id = key_path.stem.replace("AuthKey_", "")

def token():
    return jwt.encode(
        {
            "iss": issuer,
            "iat": int(time.time()),
            "exp": int(time.time()) + 1200,
            "aud": "appstoreconnect-v1",
        },
        key_path.read_text(),
        algorithm="ES256",
        headers={"kid": key_id},
    )

def api(method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"https://api.appstoreconnect.apple.com{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token()}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            payload = json.loads(raw)
        except Exception:
            payload = {"raw": raw}
        return e.code, payload

status, existing = api(
    "GET",
    f"/v1/bundleIds?filter[identifier]={bundle_id}&limit=1",
)
if status >= 400:
    raise SystemExit(f"list bundleIds failed ({status}): {existing}")
bids = existing.get("data") or []
if bids:
    bid_id = bids[0]["id"]
    print(f"bundleId exists: {bundle_id} ({bid_id})")
else:
    status, created = api(
        "POST",
        "/v1/bundleIds",
        {
            "data": {
                "type": "bundleIds",
                "attributes": {
                    "identifier": bundle_id,
                    "name": app_name,
                    "platform": "IOS",
                },
            }
        },
    )
    if status >= 400:
        raise SystemExit(f"create bundleId failed ({status}): {created}")
    bid_id = created["data"]["id"]
    print(f"created bundleId: {bundle_id} ({bid_id})")

status, apps = api("GET", f"/v1/apps?filter[bundleId]={bundle_id}&limit=1")
if status >= 400:
    raise SystemExit(f"list apps failed ({status}): {apps}")
if apps.get("data"):
    app = apps["data"][0]
    print(f"app exists: {app['attributes'].get('name')} appleId={app['id']}")
else:
    status, created = api(
        "POST",
        "/v1/apps",
        {
            "data": {
                "type": "apps",
                "attributes": {
                    "bundleId": bundle_id,
                    "name": app_name,
                    "primaryLocale": locale,
                    "sku": sku,
                },
            }
        },
    )
    if status >= 400:
        print(
            f"warning: create app failed ({status}): API key cannot CREATE apps.\n"
            f"  Create the app once in App Store Connect (Account Holder / Admin):\n"
            f"  https://appstoreconnect.apple.com/apps\n"
            f"  Name={app_name}  Bundle ID={bundle_id}  SKU={sku}  Primary locale={locale}\n"
            f"  Then re-run: npm run publish:testflight\n"
            f"  Detail: {created}",
            file=sys.stderr,
        )
        raise SystemExit(0)
    app = created["data"]
    print(f"created app: {app_name} appleId={app['id']}")

print("ASC ready for TestFlight uploads.")
PY
