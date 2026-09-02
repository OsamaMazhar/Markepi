#!/usr/bin/env python3
"""One-off: apply the ASO-recommended name, subtitle, and keywords to Markepi
in App Store Connect.

What it does, in order:
  1. PATCHes the editable App Info's en-US localization: name + subtitle.
     (Both iOS versions are READY_FOR_SALE and locked, but ASC keeps a
     separate PREPARE_FOR_SUBMISSION App Info record for name/subtitle/
     category edits — that's editable right now, no new version needed.)
  2. Creates a new iOS App Store version (metadata draft only — no build
     attached, nothing submitted, nothing goes live) since keywords live on
     the version, not the App Info, and both existing iOS versions are locked.
  3. Creates that version's en-US localization with the new keywords,
     copying description/promotionalText/marketingUrl/supportUrl forward
     from the current live version so the draft isn't missing fields.

Nothing here submits for review or uploads a build. The new version sits in
ASC as a draft (PREPARE_FOR_SUBMISSION) until you attach a build and submit
it yourself, same as clicking "+ Version" in the web UI.

Run: python3 tools/aso/apply-metadata.py
Auth: same as aso.py — ASC_ISSUER_ID env var + ~/.appstoreconnect/AuthKey_*.p8
"""
import glob, json, os, ssl, sys, time, urllib.error, urllib.request

# python.org's Python.framework ships its own (empty) cert store rather than
# using the system keychain, so urllib fails to verify Apple's chain unless
# SSL_CERT_FILE happens to be set. certifi is already a transitive dependency
# here; point at its bundle explicitly so this works in any shell.
try:
    import certifi
    SSL_CTX = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    SSL_CTX = None

APP_ID = "6782552371"
NEW_VERSION = "1.1.1"  # bump if you've already claimed this elsewhere

NEW_NAME = "Markepi: Watermark & C2PA"
NEW_SUBTITLE = "Photo & Video Date Stamp"

# Exactly 100/100 chars. No space after commas — a space costs a character and
# buys nothing; Apple tokenises on the comma. Nothing here repeats a word
# already in NEW_NAME or NEW_SUBTITLE (watermark, c2pa, photo, video, date,
# stamp) because those are already indexed and repeating them wastes the field.
# Order is by measured Apple Ads exact-match popularity, highest first.
NEW_KEYWORDS = "ai,free,font,editor,timestamp,privacy,secure,batch,proof,signature,logo,frame,exif,copyright,overlay"


def token():
    import jwt
    kid = os.path.basename(glob.glob(os.path.expanduser("~/.appstoreconnect/AuthKey_*.p8"))[0])[8:-3]
    iss = os.environ["ASC_ISSUER_ID"]
    key = open(os.path.expanduser(f"~/.appstoreconnect/AuthKey_{kid}.p8")).read()
    now = int(time.time())
    return jwt.encode({"iss": iss, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                       key, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})


def call(method, path, tok, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path,
                                  data=data, method=method,
                                  headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60, context=SSL_CTX) as r:
            b = r.read()
            return json.loads(b) if b else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code} on {method} {path}: {e.read().decode()}")


def main():
    tok = token()

    # 1. name + subtitle, on the editable App Info.
    infos = call("GET", f"/v1/apps/{APP_ID}/appInfos", tok)["data"]
    editable = next((ai for ai in infos if ai["attributes"]["appStoreState"] == "PREPARE_FOR_SUBMISSION"), None)
    if not editable:
        sys.exit("No editable (PREPARE_FOR_SUBMISSION) App Info found — check ASC by hand.")
    locs = call("GET", f"/v1/appInfos/{editable['id']}/appInfoLocalizations", tok)["data"]
    en = next(l for l in locs if l["attributes"]["locale"] == "en-US")
    resp = call("PATCH", f"/v1/appInfoLocalizations/{en['id']}", tok, {
        "data": {"type": "appInfoLocalizations", "id": en["id"],
                  "attributes": {"name": NEW_NAME, "subtitle": NEW_SUBTITLE}},
    })
    print("name:", resp["data"]["attributes"]["name"])
    print("subtitle:", resp["data"]["attributes"]["subtitle"])

    # 2. the draft version — reuse it if a previous run already made it.
    versions = call("GET", f"/v1/apps/{APP_ID}/appStoreVersions?limit=20", tok)["data"]
    ios = [v for v in versions if v["attributes"]["platform"] == "IOS"]
    new_v = next((v for v in ios if v["attributes"]["versionString"] == NEW_VERSION), None)
    if new_v:
        print("reusing existing version:", NEW_VERSION, new_v["id"])
    else:
        new_v = call("POST", "/v1/appStoreVersions", tok, {
            "data": {"type": "appStoreVersions",
                      "attributes": {"platform": "IOS", "versionString": NEW_VERSION},
                      "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}},
        })["data"]
        print("created version:", NEW_VERSION, new_v["id"])

    # 3. keywords. Apple auto-creates the en-US localization alongside a new
    # version (copying the previous version's text forward), so this is a PATCH
    # of what is already there, not a POST — POSTing it returns 409 DUPLICATE.
    vlocs = call("GET", f"/v1/appStoreVersions/{new_v['id']}/appStoreVersionLocalizations", tok)["data"]
    ven = next((l for l in vlocs if l["attributes"]["locale"] == "en-US"), None)
    if ven:
        call("PATCH", f"/v1/appStoreVersionLocalizations/{ven['id']}", tok, {
            "data": {"type": "appStoreVersionLocalizations", "id": ven["id"],
                      "attributes": {"keywords": NEW_KEYWORDS}},
        })
    else:
        # No auto-created localization: create it, carrying the live version's
        # text forward so the draft is not missing required fields.
        live = next(v for v in ios if v["attributes"]["appStoreState"] == "READY_FOR_SALE")
        live_locs = call("GET", f"/v1/appStoreVersions/{live['id']}/appStoreVersionLocalizations", tok)["data"]
        carry = next(l for l in live_locs if l["attributes"]["locale"] == "en-US")["attributes"]
        call("POST", "/v1/appStoreVersionLocalizations", tok, {
            "data": {"type": "appStoreVersionLocalizations",
                      "attributes": {
                          "locale": "en-US",
                          "keywords": NEW_KEYWORDS,
                          "description": carry.get("description"),
                          "promotionalText": carry.get("promotionalText"),
                          "marketingUrl": carry.get("marketingUrl"),
                          "supportUrl": carry.get("supportUrl"),
                      },
                      "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": new_v["id"]}}}},
        })
    print("keywords:", NEW_KEYWORDS)

    # Read back what ASC actually stored, rather than trusting the writes.
    vlocs = call("GET", f"/v1/appStoreVersions/{new_v['id']}/appStoreVersionLocalizations", tok)["data"]
    ven = next(l for l in vlocs if l["attributes"]["locale"] == "en-US")
    a = ven["attributes"]
    print("\n--- verified from ASC ---")
    print("  keywords:   ", a.get("keywords"))
    print("  description:", "present" if a.get("description") else "MISSING")
    print("  supportUrl: ", a.get("supportUrl") or "MISSING")
    print("\nDone. Nothing was submitted — the new version sits in ASC as a draft")
    print("until you attach a build and submit it yourself.")


if __name__ == "__main__":
    main()
