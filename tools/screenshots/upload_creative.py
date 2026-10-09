"""Uploads a creative asset to the ASC asset library and places it on a version (replacing the old placement).

    ASC_ISSUER_ID=… python3 upload_creative.py <version> <header|search> <file.png>

header → PRODUCT_PAGE_HEADER_ASSET, search → APP_STORE_SEARCH_RESULTS_ASSET (en-US).
"""
import jwt, time, requests, os, sys
APP, VER, KIND, PATH = "6782552371", sys.argv[1], sys.argv[2], sys.argv[3]
PLACE = {"header": "PRODUCT_PAGE_HEADER_ASSET", "search": "APP_STORE_SEARCH_RESULTS_ASSET"}[KIND]
KEY = open(os.path.expanduser("~/.appstoreconnect/AuthKey_U5B2XBFUSU.p8")).read()
B = "https://api.appstoreconnect.apple.com/v1"


def H():
    t = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                    "aud": "appstoreconnect-v1"}, KEY, algorithm="ES256", headers={"kid": "U5B2XBFUSU"})
    return {"Authorization": f"Bearer {t}", "Content-Type": "application/json"}


def ok(r):
    if r.status_code >= 300: raise SystemExit(f"{r.status_code} {r.text[:400]}")
    return r.json() if r.text else {}


vs = {v["attributes"]["versionString"]: v["id"] for v in
      ok(requests.get(f"{B}/apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=5", headers=H()))["data"]}
loc = next(x for x in ok(requests.get(f"{B}/appStoreVersions/{vs[VER]}/appStoreVersionLocalizations", headers=H()))["data"]
           if x["attributes"]["locale"] == "en-US")["id"]
data = open(PATH, "rb").read()
img = ok(requests.post(f"{B}/appAssetLibraryImages", headers=H(), json={"data": {"type": "appAssetLibraryImages",
    "attributes": {"category": "CREATIVE_ASSETS", "fileName": os.path.basename(PATH), "fileSize": len(data)},
    "relationships": {"assetLibrary": {"data": {"type": "appAssetLibraries", "id": APP}}}}}))["data"]
for op in img["attributes"]["uploadOperations"]:
    r = requests.request(op["method"], op["url"], headers={h["name"]: h["value"] for h in op["requestHeaders"]},
                         data=data[op["offset"]:op["offset"] + op["length"]])
    if r.status_code >= 300: raise SystemExit(f"chunk {r.status_code} {r.text[:200]}")
ok(requests.patch(f"{B}/appAssetLibraryImages/{img['id']}", headers=H(),
                  json={"data": {"type": "appAssetLibraryImages", "id": img["id"], "attributes": {"uploaded": True}}}))
for _ in range(40):  # Apple checks the file; a JPEG header was rejected (INVALID_ASSET_FILE_FORMAT), PNG works
    st = ok(requests.get(f"{B}/appAssetLibraryImages/{img['id']}", headers=H()))["data"]["attributes"]["state"]
    if st not in ("UPLOAD_COMPLETE", "AWAITING_UPLOAD", "PROCESSING"): break
    time.sleep(5)
print("image", st)
for old in ok(requests.get(f"{B}/appStoreVersionLocalizations/{loc}/placements?limit=80", headers=H()))["data"]:
    if old["attributes"]["placementType"] == PLACE:
        ok(requests.delete(f"{B}/appAssetLibraryPlacements/{old['id']}", headers=H())); print("removed", old["id"])
p = ok(requests.post(f"{B}/appAssetLibraryPlacements", headers=H(), json={"data": {"type": "appAssetLibraryPlacements",
    "attributes": {"placementType": PLACE}, "relationships": {
        "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc}},
        "image": {"data": {"type": "appAssetLibraryImages", "id": img["id"]}}}}}))["data"]
for _ in range(20):
    st = ok(requests.get(f"{B}/appAssetLibraryPlacements/{p['id']}", headers=H()))["data"]["attributes"]["state"]
    if st != "PENDING": break
    time.sleep(4)
print("placed", PLACE, st)  # ACTIVE = live on the version
