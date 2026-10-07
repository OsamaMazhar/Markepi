"""Cuts the v2.0 recordings (rec2/) into web/frames/v2_*/ for reel2.html.

Same rules as build.py: every recording is resampled to constant 30 fps first,
and segment times are video time of that CFR copy, read off a contact sheet.

    python3 build2.py
"""
import os
import build

build.REC = os.path.join(build.D, "rec2")

FRAMES = [("classic", 5.0), ("gallery", 9.0), ("print", 12.5), ("banner", 17.0), ("float", 23.5), ("tone", 27.5),
          ("swatch", 32.0), ("spine", 39.0), ("noir", 42.0), ("readout", 45.5), ("ambient", 50.0), ("aura", 56.5),
          ("blend", 60.5), ("emboss", 66.0), ("sunlight", 75.0)]

# name: (recording, start s, end s, speed)
SEGMENTS = {
    **{f"v2_st_{n}": ("frames", t, t + 0.3, 1) for n, t in FRAMES},
    "v2_st_glow": ("glow", 4.0, 4.3, 1),
    "v2_border": ("options", 3.8, 10.8, 3.5),      # border wider, then thinner
    "v2_gradient": ("options", 14.8, 17.6, 1.9),   # gradient on
    "v2_keyline": ("options", 19.6, 25.4, 3.9),    # keyline off, then on
    "v2_caption": ("caption", 1.5, 11.5, 4.5),     # caption fields on and off
    "v2_looks": ("looks", 2.5, 32.4, 7.5),         # moods, then film stocks
    "v2_textmove": ("textmove", 2.0, 11.8, 3.6),   # text dragged anywhere
    "v2_textsize": ("textsize", 6.0, 35.0, 11),    # text bigger, then smaller
    "v2_logomove": ("logomove", 2.0, 14.5, 4.0),   # logo dragged to custom spots
}

if __name__ == "__main__":
    for name, (src, a, b, sp) in SEGMENTS.items():
        print(f"{name:14s} {build.cut(name, src, a, b, sp):4d} frames")
