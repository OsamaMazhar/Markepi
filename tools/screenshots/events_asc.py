"""Creates an in-app event from events.js as a draft in App Store Connect, with its en-US text and media.

    source ~/.zshrc   # ASC_ISSUER_ID
    python3 events_asc.py looks      # id from events.js; media from events-render.mjs

The event shows in every territory, published when it starts (09:00 UTC), so back-to-back events never overlap
on the store. It stays a draft: submitting is a separate step (asc-event-guide.md). Run again after a re-render:
an event with the same name is reused, its text updated and its media replaced. The schedule is set only on create.
"""
import calendar, json, jwt, os, requests, subprocess, sys, time

APP = "6782552371"
KEY = open(os.path.expanduser("~/.appstoreconnect/AuthKey_U5B2XBFUSU.p8")).read()
B = "https://api.appstoreconnect.apple.com/v1"
OUT = os.path.join(os.environ.get("MARKEPI_ASSETS", os.path.expanduser("~/Projects/Markepi-Assets")), "events")


def H():
    t = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                    "aud": "appstoreconnect-v1"}, KEY, algorithm="ES256", headers={"kid": "U5B2XBFUSU"})
    return {"Authorization": f"Bearer {t}", "Content-Type": "application/json"}


def ok(r):
    if r.status_code >= 300: raise SystemExit(f"{r.status_code} {r.text[:400]}")
    return r.json() if r.text else {}


get = lambda u: ok(requests.get(B + u, headers=H()))
post = lambda u, d: ok(requests.post(B + u, headers=H(), json={"data": d}))
patch = lambda u, d: ok(requests.patch(B + u, headers=H(), json={"data": d}))


def put(ops, data):
    for op in ops:
        r = requests.request(op["method"], op["url"], headers={h["name"]: h["value"] for h in op["requestHeaders"]},
                             data=data[op["offset"]:op["offset"] + op["length"]])
        if r.status_code >= 300: raise SystemExit(f"chunk {r.status_code} {r.text[:200]}")


ev_id = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
events = json.loads(subprocess.check_output(["node", "-e", "global.window={};require('./events.js');console.log(JSON.stringify(window.EVENTS))"], cwd=here))
ev = next(e for e in events if e["id"] == ev_id)
day = lambda d: time.strftime("%Y-%m-%dT09:00:00.000Z", time.gmtime(calendar.timegm(time.strptime(d, "%Y-%m-%d"))))

event = next((e for e in get(f"/apps/{APP}/appEvents?limit=50")["data"] if e["attributes"]["referenceName"].startswith(ev["name"] + " (")), None)
territories = [t["id"] for t in get("/territories?limit=200")["data"]]
event = event or post("/appEvents", {"type": "appEvents", "attributes": {
    "referenceName": f"{ev['name']} ({ev['start'][:7]})", "badge": ev["badge"], "primaryLocale": "en-US",
    "priority": "HIGH", "purpose": "APPROPRIATE_FOR_ALL_USERS", "purchaseRequirement": ev.get("purchase", "NO_COST_ASSOCIATED"),
    "deepLink": ev.get("deepLink", "watermark://open"),  # any watermark:// URL just opens the app (MarkepiApp.onOpenURL)
    "territorySchedules": [{"territories": territories, "publishStart": day(ev["start"]),
                            "eventStart": day(ev["start"]), "eventEnd": day(ev["end"])}]},
    "relationships": {"app": {"data": {"type": "apps", "id": APP}}}})["data"]
print("event", event["id"])

locs = get(f"/appEvents/{event['id']}/localizations")["data"]
loc = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
text = {"name": ev["name"], "shortDescription": ev["short"], "longDescription": ev["long"]}
if loc: patch(f"/appEventLocalizations/{loc['id']}", {"type": "appEventLocalizations", "id": loc["id"], "attributes": text})
else: loc = post("/appEventLocalizations", {"type": "appEventLocalizations", "attributes": {"locale": "en-US", **text},
                 "relationships": {"appEvent": {"data": {"type": "appEvents", "id": event["id"]}}}})["data"]

for old in get(f"/appEventLocalizations/{loc['id']}/appEventScreenshots")["data"]:
    ok(requests.delete(f"{B}/appEventScreenshots/{old['id']}", headers=H()))
for kind, asset in [("card", "EVENT_CARD"), ("detail", "EVENT_DETAILS_PAGE")]:
    data = open(f"{OUT}/{ev_id}-{kind}.png", "rb").read()
    shot = post("/appEventScreenshots", {"type": "appEventScreenshots", "attributes": {
        "fileName": f"{ev_id}-{kind}.png", "fileSize": len(data), "appEventAssetType": asset},
        "relationships": {"appEventLocalization": {"data": {"type": "appEventLocalizations", "id": loc["id"]}}}})["data"]
    put(shot["attributes"]["uploadOperations"], data)
    patch(f"/appEventScreenshots/{shot['id']}", {"type": "appEventScreenshots", "id": shot["id"], "attributes": {"uploaded": True}})
    for _ in range(30):
        state = get(f"/appEventScreenshots/{shot['id']}")["data"]["attributes"].get("assetDeliveryState", {}).get("state")
        if state not in ("AWAITING_UPLOAD", "UPLOAD_COMPLETE"): break
        time.sleep(4)
    print(kind, state)
print(get(f"/appEvents/{event['id']}")["data"]["attributes"]["eventState"])
