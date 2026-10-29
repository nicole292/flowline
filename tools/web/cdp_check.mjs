// Loads a page in headless Chrome over the DevTools protocol, waits in real
// time, optionally taps/presses keys, logs console output and saves screenshots.
//   node tools/web/cdp_check.mjs <url> <out_prefix> [seconds]
import { spawn } from "node:child_process";
import { writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [url, out, secs = "40"] = process.argv.slice(2);
const chrome = "C:/Program Files/Google/Chrome/Application/chrome.exe";
const port = 9333;
const proc = spawn(chrome, ["--headless=new", `--remote-debugging-port=${port}`, "--window-size=1280,640",
  "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--autoplay-policy=no-user-gesture-required",
  `--user-data-dir=${mkdtempSync(join(tmpdir(), "cdp-"))}`, "about:blank"], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let targets;
for (let i = 0; i < 40; i++) {
  try { targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); break; } catch { await sleep(250); }
}
const page = targets.find((t) => t.type === "page");
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener("open", r));
let id = 0;
const pending = new Map();
ws.addEventListener("message", (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); }
  if (m.method === "Runtime.consoleAPICalled") {
    console.log("console." + m.params.type + ":", m.params.args.map((a) => a.value ?? a.description).join(" "));
  }
  if (m.method === "Runtime.exceptionThrown") console.log("EXCEPTION:", m.params.exceptionDetails.exception?.description);
});
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const shot = async (name) => {
  const r = await send("Page.captureScreenshot", { format: "png" });
  writeFileSync(`${out}_${name}.png`, Buffer.from(r.data, "base64"));
  console.log("SHOT", name);
};
const tap = async (x, y) => {
  for (const type of ["mousePressed", "mouseReleased"]) {
    await send("Input.dispatchMouseEvent", { type, x, y, button: "left", clickCount: 1 });
  }
};
const key = async (code, ms) => {
  const k = { key: code, code, windowsVirtualKeyCode: { ArrowLeft: 37, ArrowRight: 39 }[code] };
  await send("Input.dispatchKeyEvent", { type: "rawKeyDown", ...k });
  await sleep(ms);
  await send("Input.dispatchKeyEvent", { type: "keyUp", ...k });
};

await send("Runtime.enable");
await send("Page.enable");
await send("Page.navigate", { url });
const t0 = Date.now();
await sleep(Number(secs) * 1000);
await shot("menu");
console.log("elapsed", ((Date.now() - t0) / 1000).toFixed(0), "s");
await tap(180, 410);   // DRIVE button (left column)
await sleep(6000);
await key("ArrowLeft", 600);
await sleep(4000);
await shot("play");
proc.kill();
process.exit(0);
