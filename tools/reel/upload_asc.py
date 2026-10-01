"""Puts ~/Desktop/Markepi-Reel.mp4 in the en-US IPHONE_67 app preview set of a version (replacing what is there).

    ASC_ISSUER_ID=… python3 upload_asc.py [version]     # default 1.5
"""
import jwt, time, requests, os, sys, hashlib
APP, VER = "6782552371", (sys.argv[1] if len(sys.argv) > 1 else "1.5")
PATH = os.path.expanduser("~/Desktop/Markepi-Reel.mp4")
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
l = next(x for x in ok(requests.get(f"{B}/appStoreVersions/{vs[VER]}/appStoreVersionLocalizations", headers=H()))["data"]
         if x["attributes"]["locale"] == "en-US")
sets = ok(requests.get(f"{B}/appStoreVersionLocalizations/{l['id']}/appPreviewSets", headers=H()))["data"]
s = next((x for x in sets if x["attributes"]["previewType"] == "IPHONE_67"), None) or ok(requests.post(
    f"{B}/appPreviewSets", headers=H(), json={"data": {"type": "appPreviewSets", "attributes": {"previewType": "IPHONE_67"},
    "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": l["id"]}}}}}))["data"]
for old in ok(requests.get(f"{B}/appPreviewSets/{s['id']}/appPreviews", headers=H()))["data"]:
    ok(requests.delete(f"{B}/appPreviews/{old['id']}", headers=H())); print("removed", old["id"])
data = open(PATH, "rb").read()
p = ok(requests.post(f"{B}/appPreviews", headers=H(), json={"data": {"type": "appPreviews", "attributes": {
    "fileName": os.path.basename(PATH), "fileSize": len(data), "mimeType": "video/mp4"},
    "relationships": {"appPreviewSet": {"data": {"type": "appPreviewSets", "id": s["id"]}}}}}))["data"]
for op in p["attributes"]["uploadOperations"]:
    r = requests.request(op["method"], op["url"], headers={h["name"]: h["value"] for h in op["requestHeaders"]},
                         data=data[op["offset"]:op["offset"] + op["length"]])
    if r.status_code >= 300: raise SystemExit(f"chunk {r.status_code} {r.text[:200]}")
ok(requests.patch(f"{B}/appPreviews/{p['id']}", headers=H(), json={"data": {"type": "appPreviews", "id": p["id"], "attributes": {
    "uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest(), "previewFrameTimeCode": "00:00:28:00"}}}))
print("uploaded", p["id"])
for _ in range(40):  # Apple transcodes the video; wait for the verdict
    st = ok(requests.get(f"{B}/appPreviews/{p['id']}", headers=H()))["data"]["attributes"]["assetDeliveryState"]
    print(st["state"], st.get("errors") or "", flush=True)
    if st["state"] in ("COMPLETE", "FAILED"): break
    time.sleep(15)
