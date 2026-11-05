"""Shows an in-app event's media the way App Store Connect lays it out, before anything is uploaded.

    python3 events-mock.py looks frames share    # → $MARKEPI_ASSETS/events/<id>-mock.jpg

Card: the store trims about 96 px off each side (it shows a 16:10 window of the 1920×1080 card), puts the
app icon in a circle at the top right and writes the badge, name and short description over a dark
gradient at the bottom left. The detail page sits beside it, unchanged. See asc-event-guide.md.
"""
import json, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

here = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.environ.get("MARKEPI_ASSETS", os.path.expanduser("~/Projects/Markepi-Assets")), "events")
events = {e["id"]: e for e in json.loads(subprocess.check_output(
    ["node", "-e", "global.window={};require('./events.js');console.log(JSON.stringify(window.EVENTS))"], cwd=here))}
FONT = "/System/Library/Fonts/SFNS.ttf"
BADGE = {"SPECIAL_EVENT": "SPECIAL EVENT", "MAJOR_UPDATE": "MAJOR UPDATE", "NEW_SEASON": "NEW SEASON",
         "LIVE_EVENT": "LIVE EVENT", "PREMIERE": "PREMIERE", "CHALLENGE": "CHALLENGE", "COMPETITION": "COMPETITION"}

for ev_id in sys.argv[1:]:
    ev = events[ev_id]
    card = Image.open(f"{OUT}/{ev_id}-card.png").convert("RGBA").crop((96, 0, 1824, 1080))
    shade = Image.new("RGBA", card.size); d = ImageDraw.Draw(shade)
    for y in range(600, 1080): d.line([(0, y), (card.width, y)], fill=(0, 0, 0, int(200 * (y - 600) / 480)))
    card = Image.alpha_composite(card, shade); d = ImageDraw.Draw(card)
    d.ellipse((1488, 61, 1670, 243), fill=(60, 70, 65, 235))  # the app icon, in card coordinates 1584–1766 × 61–243
    d.text((90, 760), BADGE.get(ev["badge"], ev["badge"]), font=ImageFont.truetype(FONT, 54), fill=(200, 200, 200))
    d.text((90, 830), ev["name"], font=ImageFont.truetype(FONT, 82), fill="white")
    d.text((90, 940), ev["short"], font=ImageFont.truetype(FONT, 62), fill=(210, 210, 210))
    detail = Image.open(f"{OUT}/{ev_id}-detail.png").convert("RGB").resize((608, 1080))
    mock = Image.new("RGB", (card.width + 30 + 608, 1080), "white")
    mock.paste(card.convert("RGB"), (0, 0)); mock.paste(detail, (card.width + 30, 0))
    mock.save(f"{OUT}/{ev_id}-mock.jpg", quality=85)
    print("mock", f"{OUT}/{ev_id}-mock.jpg")
