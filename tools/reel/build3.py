"""Cuts the iPad recordings (rec3/) into web/frames/ip_*/ for reel2-ipad.html (1200x1600 App Store iPad preview).

    python3 build3.py
"""
import os
import build

build.REC = os.path.join(build.D, "rec3")
build.W = 750   # the iPad screen's width inside the reel (3:4)

FRAMES = [("classic", 2.0), ("gallery", 11.0), ("print", 16.0), ("banner", 22.0), ("float", 27.0), ("tone", 33.0),
          ("swatch", 39.0), ("spine", 44.0), ("noir", 50.0), ("readout", 56.0), ("ambient", 66.0), ("aura", 72.0),
          ("blend", 77.0), ("emboss", 83.0), ("sunlight", 89.0), ("glow", 94.4)]

SEGMENTS = {
    **{f"ip_st_{n}": ("frames", t, t + 0.3, 1) for n, t in FRAMES},
    "ip_border": ("options", 3.5, 12.0, 4.2),
    "ip_gradient": ("options", 14.8, 17.6, 1.9),
    "ip_keyline": ("options", 19.6, 26.5, 4.6),
    "ip_caption": ("caption", 1.5, 22.0, 9.2),
    "ip_looks": ("looks", 2.5, 32.0, 7.4),
    "ip_textmove": ("textmove", 2.0, 11.8, 3.6),
    "ip_textsize": ("textsize", 2.0, 36.0, 12.9),
    "ip_logomove": ("logomove", 2.0, 14.5, 4.0),
}

if __name__ == "__main__":
    for name, (src, a, b, sp) in SEGMENTS.items():
        print(f"{name:14s} {build.cut(name, src, a, b, sp):4d} frames")
