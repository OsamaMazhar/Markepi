// node render.mjs                -> the film in $MARKEPI_MV/out/
// node render.mjs 45,335         -> PNG stills in stills/
// node render.mjs --audio-only   -> remix audio onto the last silent.mp4
// Picture: promo.html (GSAP timeline seeked per frame). Audio: music-stolen-128bpm + SFX + narrator, -14 LUFS.
import { chromium } from "playwright";
import { existsSync, mkdirSync, symlinkSync, writeFileSync } from "fs";
import { spawn, execFileSync } from "child_process";
import os from "os";
import path from "path";

const dir = path.dirname(new URL(import.meta.url).pathname);
// Media stays out of git: music/SFX/VO + out/ live in the marketing-videos folder, slides in the release screenshots
const root = process.env.MARKEPI_MV || path.join(os.homedir(), "Projects/Markepi-Assets/marketing-videos");
for (const [link, target] of [
  ["slides", process.env.MARKEPI_SLIDES || path.join(os.homedir(), "Projects/Markepi-Assets/v1.5-screenshots")],
  ["frames", path.join(dir, "../reel/web/frames")],   // app recordings, built by tools/reel/build.py
  ["icon.png", path.join(dir, "../reel/web/icon.png")],
]) if (!existsSync(path.join(dir, link))) symlinkSync(target, path.join(dir, link));
const audioOnly = process.argv[2] === "--audio-only";
const only = process.argv[2] && !audioOnly ? process.argv[2].split(",").map(Number) : null;
const stills = path.join(dir, "stills");
mkdirSync(stills, { recursive: true });

const browser = await chromium.launch({ args: ["--allow-file-access-from-files", "--font-render-hinting=none", "--enable-gpu-rasterization"] });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
page.on("pageerror", e => { console.error(e); process.exit(1); });
await page.goto(`file://${dir}/promo.html`);
await page.waitForFunction(() => window.READY, null, { timeout: 60000 });
const total = await page.evaluate(() => window.TOTAL_FRAMES);
const frames = audioOnly ? [] : only || [...Array(total).keys()];

const date = new Date().toISOString().slice(0, 10).replace(/-/g, "");
const silent = path.join(dir, "silent.mp4");
const enc = only || audioOnly ? null : spawn("ffmpeg", ["-v", "error", "-y", "-f", "image2pipe", "-framerate", "30", "-i", "-",
  "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-r", "30", silent], { stdio: ["pipe", "inherit", "inherit"] });
for (const f of frames) {
  await page.evaluate(f => window.renderAt(f), f);
  const buf = await page.screenshot(only ? { type: "png" } : { type: "jpeg", quality: 95 });
  if (only) writeFileSync(path.join(stills, `${String(f).padStart(4, "0")}.png`), buf);
  else if (!enc.stdin.write(buf)) await new Promise(r => enc.stdin.once("drain", r));
  if (f % 90 === 0) process.stdout.write(`${f}/${total} `);
}
await browser.close();
if (only) process.exit(0);
if (enc) { enc.stdin.end(); await new Promise(r => enc.on("close", r)); }

// ---- audio: music + SFX on the big cuts (times in seconds, beat grid from promo.html)
const b = k => 0.459 + k * 60 / 128, D = total / 30;
const A = p => path.join(root, "assets/audio", p);
const sfx = [["sfx-whoosh.wav", b(8) - 0.45, 0.7], ["sfx-whoosh.wav", b(16) - 0.4, 0.5], ["sfx-thud.wav", b(32), 0.9], ["sfx-whoosh.wav", b(40) - 0.6, 0.6], ["sfx-chime.wav", b(40), 0.6]];
// narrator lines (tools/vo_make.py, build/lines-wide.json), one per scene
const vo = [["vo-wd-1.wav", 0.35], ["vo-wd-2.wav", b(8) + 0.05], ["vo-wd-3.wav", b(19) + 0.1], ["vo-wd-4.wav", b(32) + 0.3], ["vo-wd-5.wav", b(42)]];
const ms = t => Math.round(t * 1000);
const inputs = ["-i", silent, "-i", A("music-stolen-128bpm.wav"), ...sfx.flatMap(([f]) => ["-i", A(f)]), ...vo.flatMap(([f]) => ["-i", A(f)])];
const nV = vo.length, o = 2 + sfx.length;
const fc = [`[1:a]atrim=0:${D},afade=t=out:st=${(D - 1.4).toFixed(2)}:d=1.4,aformat=channel_layouts=stereo[m]`,
  ...sfx.map(([, t, v], i) => `[${i + 2}:a]volume=${v},adelay=${ms(t)}|${ms(t)},aformat=channel_layouts=stereo[s${i}]`),
  ...vo.map(([, t], i) => `[${o + i}:a]adelay=${ms(t)}|${ms(t)},aformat=channel_layouts=stereo[v${i}]`),
  `${vo.map((_, i) => `[v${i}]`).join("")}amix=inputs=${nV}:normalize=0,volume=2.2,apad,atrim=0:${D},asplit[vo][key]`,
  // music ducks under the voice
  `[m][key]sidechaincompress=threshold=0.02:ratio=6:attack=20:release=350[md]`,
  `[md]${sfx.map((_, i) => `[s${i}]`).join("")}[vo]amix=inputs=${sfx.length + 2}:normalize=0,loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[a]`];
const out = path.join(root, "out", `markepi_reddit-wide_${Math.round(D)}s_v03_${date}.mp4`);
execFileSync("ffmpeg", ["-v", "error", "-y", ...inputs, "-filter_complex", fc.join(";"), "-map", "0:v", "-map", "[a]",
  "-c:v", "copy", "-c:a", "aac", "-b:a", "256k", "-shortest", "-movflags", "+faststart", out], { stdio: "inherit" });
console.log("\n" + out);
