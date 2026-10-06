// node still.mjs -> stills/markepi-reddit-still.png (1920x1080, still.html)
import { chromium } from "playwright";
import path from "node:path";
const dir = path.dirname(new URL(import.meta.url).pathname);
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
await p.goto("file://" + path.join(dir, "still.html"));
await p.waitForLoadState("networkidle");
await p.screenshot({ path: path.join(dir, "stills/markepi-reddit-still.png") });
await b.close();
