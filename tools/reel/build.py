"""Cuts the simulator screen recordings into the frame folders web/reel.html plays.

Simulator recordings (`xcrun simctl io <udid> recordVideo`) are variable frame rate:
a frame is written only when the screen changes. Every segment is resampled to
constant 30 fps here, so `n` frames in reel.html is always n/30 seconds.

    python3 build.py            # -> web/frames/<segment>/0001.jpg …
"""
import os, shutil, subprocess, sys

D = os.path.dirname(os.path.abspath(__file__))
REC = os.environ.get("REC", os.path.join(D, "rec"))   # the .mp4s from rec.sh (gitignored)
OUT = os.path.join(D, "web", "frames")
W = 712                                               # the reel's screen width; height follows the 1320x2868 capture

# name: (recording, start s, end s, speed)
SEGMENTS = {
    # 01 frames — one short hold per style, cut from the style-cycling take
    **{f"st_{n}": ("frames", t, t + 0.4, 1) for n, t in [
        ("float", 11), ("swatch", 1.2), ("tone", 17), ("noir", 52), ("readout", 61), ("ambient", 66),
        ("aura", 72), ("blend", 81), ("emboss", 86), ("sunlight", 95)]},
    # 02 text — typing the studio name, then the result with the panel closed
    "typing": ("text", 4.8, 13.0, 2.2),
    "typed": ("text", 19.5, 20.0, 1),
    # 03 video — scrubbing a clip with the watermark on it
    "video": ("video", 1.0, 8.5, 2.5),
    # logo — position menu: top left, centre, bottom right, then the panel closes on the full preview
    "lg_tl": ("logo", 4.6, 8.0, 2.2),
    "lg_c": ("logo", 10.8, 12.8, 1.8),
    "lg_br": ("logo", 24.0, 26.6, 1.8),
    "lg_close": ("logo", 33.4, 35.6, 1.1),
    # 04 share in — Photos share sheet → Markepi → the editor
    "sheet_in": ("sharein", 4.4, 6.3, 1),
    "arrive": ("sharein", 11.0, 13.0, 1),
    # 05 C2PA — sign sheet, then the signed receipt sliding up
    "sign": ("c2pa", 3.6, 7.6, 1.6),
    "signed": ("c2pa", 15.9, 20.4, 1.2),
    # 06 share out — the system share sheet
    "share_out": ("share", 18.4, 24.0, 1.2),
}


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stderr[-2000:])


def cfr(src):
    """Whole recording -> constant 30 fps once, so every cut is exact frame arithmetic."""
    out = os.path.join(REC, src + "_cfr.mp4")
    if not os.path.exists(out):
        run(["ffmpeg", "-v", "error", "-y", "-i", os.path.join(REC, src + ".mp4"), "-vf", "fps=30",
             "-fps_mode", "cfr", "-c:v", "libx264", "-crf", "12", "-preset", "fast", out])
    return out


def cut(name, src, a, b, speed):
    d = os.path.join(OUT, name)
    shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
    f0, f1 = round(a * 30), round(b * 30)
    run(["ffmpeg", "-v", "error", "-y", "-i", cfr(src), "-vf",
         f"select='between(n,{f0},{f1 - 1})',setpts=(N/30/{speed})/TB,fps=30,scale={W}:-2:flags=lanczos",
         "-fps_mode", "cfr", "-q:v", "2", os.path.join(d, "%04d.jpg")])
    return len(os.listdir(d))


if __name__ == "__main__":
    for name, (src, a, b, sp) in SEGMENTS.items():
        print(f"{name:10s} {cut(name, src, a, b, sp):4d} frames")
