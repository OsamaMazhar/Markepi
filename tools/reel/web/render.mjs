// node render.mjs <preview|showcase> [onlyFrames,comma,separated]
import { chromium } from "playwright-core";
import { mkdirSync, rmSync } from "fs";
import { execFileSync, spawn } from "child_process";
import path from "path";
import os from "os";

const mode = process.argv[2] || "preview";
const lang = process.env.RL || "en";
const only = process.argv[3] ? process.argv[3].split(",").map(Number) : null;
const dir = path.dirname(new URL(import.meta.url).pathname);
const out = path.join(dir, "out-" + mode + (mode === "reel" ? "-" + lang : ""));
if (!only) rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

const browser = await chromium.launch({
  executablePath: "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  args: ["--allow-file-access-from-files", "--font-render-hinting=none"],
});
const page = await browser.newPage({ viewport: { width: 886, height: 1920 }, deviceScaleFactor: 1 });
await page.goto(`file://${dir}/${mode === "reel" ? "reel.html?lang=" + lang : "index.html?mode=" + mode}`);
await page.waitForFunction(() => window.READY);
const total = await page.evaluate(() => window.TOTAL_FRAMES);
const frames = only || [...Array(total).keys()];
const log = [];
const dest = path.join(os.homedir(), "Desktop", mode === "reel" ? `Markepi-Reel.mp4` : `Markepi-${mode}.mp4`);
const enc = only ? null : spawn("ffmpeg", ["-v", "error", "-y", "-f", "image2pipe", "-framerate", "30", "-i", "-",
  "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100", "-map", "0:v", "-map", "1:a", "-shortest",
  "-c:v", "libx264", "-preset", "slow", "-crf", "15", "-pix_fmt", "yuv420p", "-r", "30",
  "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", dest], { stdio: ["pipe", "inherit", "inherit"] });
for (const f of frames) {
  await page.evaluate(f => window.renderAt(f), f);
  const buf = await page.screenshot({ type: "png" });
  if (only || f === 0 || f === total - 1) (await import("fs")).writeFileSync(path.join(out, `${String(f).padStart(5, "0")}.png`), buf);
  if (enc && !enc.stdin.write(buf)) await new Promise(r => enc.stdin.once("drain", r));
  if (f % 150 === 0) process.stdout.write(`${f}/${total} `);
}
await browser.close();
if (enc) { enc.stdin.end(); await new Promise(r => enc.on("close", r)); console.log("\n" + dest); }
