# In-app events on App Store Connect

Ported from AutoAlign's `tools/screenshots/asc-event-guide.md`, which holds the full measurements of what App Store
Connect draws over the media. This page keeps what Markepi needs.

| File | Job |
|---|---|
| `events.js` | Every event: id, badge, purchase requirement, start/end date, name, short and long text |
| `events.html` | Draws one event's media (`?e=<id>&s=card` or `detail`): blurred-photo backdrop, headline, 3D iPhone, prints |
| `events-render.mjs` | Renders `<id>-card.png` (1920×1080) and `<id>-detail.png` (1080×1920) |
| `events-mock.py` | Shows the card the way App Store Connect lays it out (`<id>-mock.jpg`) |
| `events_asc.py` | Creates or updates the event as a draft, with its en-US text and both images |

Media lands in `~/Projects/Markepi-Assets/events/` (`MARKEPI_ASSETS`). Screens and exports come from `cap/v2`
(local only, excluded from git): `iphone/<shot>.png` at 1320×2868, `looks/`, `styles/`, `creative/`. The iPhone 17 Pro
model is `~/Projects/Markepi-Assets/models/iphone-17-pro.glb`. Node deps: `npm i` in this folder (three, playwright-core).

## Rules

1. **Show before uploading.** Render, run `events-mock.py`, show the mocks. Upload only after the user says so.
   Creating a draft counts as an upload.
2. **Upload and submit are separate steps.** Submit only when asked.
3. **Dates never overlap.** Each event starts when the previous one ends (same day, 09:00 UTC), and
   `publishStart` equals `eventStart`. Make each event as long as allowed (31 days), starting from now.
4. **Don't submit a version along with the events.** Version 1.0 sits in `PREPARE_FOR_SUBMISSION`. Before
   submitting, list `reviewSubmissions`; never add events to one that holds an app version.
5. **Make only claims you can check.** Film looks are Pro (`PhotoLook.isFree`), so that event is
   `IN_APP_PURCHASE` (`IN_APP_PURCHASE_OR_SUBSCRIPTION` is rejected: no longer supported). Frames and watermarks are free (smaller export with the Markepi mark).
   No HDR or "proof of authorship" claims for the free tier. **Major Update** only for the event that launches
   a feature.
6. **Deep link:** `watermark://open`. Any `watermark://` URL opens the app; a bare scheme is rejected (409).

## Text limits

name 30 · short 50 · long 120. Check with
`node -e "global.window={};require('./events.js');for(const e of window.EVENTS)console.log(e.id,e.name.length,e.short.length,e.long.length)"`.

## Placement (card 1920×1080)

The store trims ~96 px off each side, draws its app icon at about x 1584–1766, y 61–243, and writes badge, name and
short text bottom left (x 96–1050, y ≈ 700–1000) over a gradient from y ≈ 600.

| Object | Where |
|---|---|
| Headline | left 200, top 100, width 760 (kicker 36, head 112, sub 46) |
| iPhone | centre 1290, 600, 860 px tall, turned −18°: top ≈ 170, left of the icon |
| Prints | centre x 1610–1655, y 520 and 820, 220 px wide: right edge ≤ 1800, below the icon |
| Second phone (share) | centre 1615, 720, 640 px tall |

Detail (1080×1920): headline centred at top 100; phone and prints from y ≈ 700 down. The store writes over the bottom
third, so nothing that must be read sits below y ≈ 1280.

## Steps

```sh
cd tools/screenshots
source ~/.zshrc                                   # ASC_ISSUER_ID
node events-render.mjs looks frames share
python3 events-mock.py looks frames share         # → show the user, wait for "upload"
python3 events_asc.py looks                       # draft + text + images
```

After upload, each image's `assetDeliveryState` goes `UPLOAD_COMPLETE` → `COMPLETE` (10–30 min). Don't submit
until all are `COMPLETE`. To submit (only when asked): `POST /v1/reviewSubmissions` (platform `IOS`), one
`POST /v1/reviewSubmissionItems` per event with an `appEvent` relationship, then `PATCH` the submission with
`submitted: true`.

## Events, as of 2026-10-29

| Event | Dates (09:00 UTC) | Badge | Purchase | State |
|---|---|---|---|---|
| Film Looks for Your Photos | Oct 30 – Nov 30 | Major Update | Pro | draft (id 6828421826) |
| Frame Your Holiday Photos | Nov 30 – Dec 31 | Special Event | free | draft (id 6828422532) |
| Watermark and Share | Dec 31 – Jan 31 | Special Event | free | draft (id 6828422443) |
