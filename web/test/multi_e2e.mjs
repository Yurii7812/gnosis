// 複数の Vault を同時に開く E2E: 実際の Electron + 本物の Vim を 2 つ同時に（別ウィンドウ・同じ HOME / Gnosis ホーム）動かす。
//   ウィンドウ1 → vault A、ウィンドウ2 → vault B。両方とも同時に使え、内容・検索・設定（配色）が混ざらない。
//   一方が終わっても、もう一方は使い続けられる。本物の vault・Gnosis ホーム・HOME には触らない。
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";

const base = process.env.TMPDIR || path.join(os.homedir(), "Desktop", "test");
fs.mkdirSync(base, { recursive: true });
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(__dirname, "..");
const realHome = os.homedir();
const tmp = fs.mkdtempSync(path.join(base, "gnosis-multi-e2e-"));
const home = path.join(tmp, "home");
const gh = path.join(tmp, "gnosis home");
fs.mkdirSync(path.join(home, ".vim"), { recursive: true });
fs.mkdirSync(path.join(gh, "plugins"), { recursive: true });
for (const b of [path.join(realHome, ".local", "share", "gnosis", "plugins"), path.join(realHome, ".vim-simple-yurii-note")]) {
  for (const name of ["fzf", "fzf.vim", "vim-surround"]) {
    const src = path.join(b, name), dst = path.join(gh, "plugins", name);
    if (fs.existsSync(src) && !fs.existsSync(dst)) fs.symlinkSync(src, dst);
  }
}
const mkVault = (name, word, settings) => {
  const v = path.join(tmp, name);
  fs.mkdirSync(path.join(v, ".gnosis"), { recursive: true });
  fs.writeFileSync(path.join(v, "index.md"), `---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n\n[${word}のノート](n.md)\n`);
  fs.writeFileSync(path.join(v, "n.md"), `---\ntime: 2026-01-01 00:00:00\ntitle: ${word}のノート\n---\n\n# ${word}のノート\n\n${word}だけの本文\n`);
  fs.writeFileSync(path.join(v, ".gnosis", "settings.json"), JSON.stringify({ version: 1, language: "ja", window: { maximized: false, width: 900, height: 700 }, ...settings }));
  return v;
};
const vA = mkVault("vault A", "アルファ", { appTheme: { kind: "custom", name: "a" }, appCustomThemes: { a: { base: "light", bg: "#f8f4e8", fg: "#222222", link: "#0b57d0", heading: "#7c2d12", selection: "#b6d6ff", cursorline: "#efe9d6" } } });
const vB = mkVault("vault B", "ベータ", {});
fs.writeFileSync(path.join(gh, "vaults.json"), JSON.stringify({ version: 1, last: vA, vaults: [{ path: vA, name: "A" }, { path: vB, name: "B" }] }));

const scenario = (tag, holdMs) => `(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const waitFor = async (fn, ms = 20000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { try { const v = fn(); if (v) return v; } catch (e) {} await sleep(80); } return null; };
  const G = await waitFor(() => window.__gui);
  await waitFor(() => G.state().file && G.state().file.endsWith('index.md') && G.state().palette && G.state().lines, 25000);
  await sleep(500);
  const snap = () => ({ vault: G.state().vault, file: G.state().file, text: (document.querySelector('.cm-content') || document.body).innerText, bg: G.state().palette && G.state().palette.bg, doc: getComputedStyle(document.documentElement).getPropertyValue('--bg').trim() });
  const R = { tag: ${JSON.stringify(tag)} };
  R.first = snap();
  // もう一方のウィンドウが動いている間、このウィンドウを使い続ける: リンクを開いて、内容を確かめる
  await sleep(${holdMs});
  G.send('\\t'); await sleep(200);
  G.send('\\r'); await sleep(1200);
  R.afterOpen = snap();
  await sleep(500);
  R.__png = "";
  return R;
})()`;

const run = (tag, vault, holdMs) => new Promise((resolve) => {
  const sp = path.join(tmp, `scenario-${tag}.js`);
  fs.writeFileSync(sp, scenario(tag, holdMs));
  const out = path.join(tmp, `out-${tag}.json`);
  const stubBin = path.join(tmp, "stub-bin");
  fs.mkdirSync(stubBin, { recursive: true });
  for (const cmd of ["wl-paste", "wl-copy", "xclip", "xsel", "qdbus6"]) fs.writeFileSync(path.join(stubBin, cmd), "#!/bin/sh\nexit 1\n", { mode: 0o755 });
  const env = { ...process.env, PATH: stubBin + path.delimiter + (process.env.PATH || ""), HOME: home, GNOSIS_HOME: gh, GNOSIS_ROOT: vault,
    GNOSIS_VIMRC: path.join(web, "..", "vimrc_gnosis"), GNOSIS_TEST_SCRIPT: sp, GNOSIS_TEST_OUT: out, LANG: "ja_JP.UTF-8" };
  delete env.WAYLAND_DISPLAY; delete env.XDG_SESSION_TYPE; delete env.DISPLAY; delete env.PKM_ROOT;
  const t0 = Date.now();
  const p = execFile("xvfb-run", ["-a", "-s", "-screen 0 1100x880x24", path.join(web, "node_modules/.bin/electron"), web, "--no-sandbox", "--disable-gpu", "--ozone-platform=x11"],
    { env, timeout: 150000 }, (err) => {
      let R = null;
      try { R = JSON.parse(fs.readFileSync(out, "utf8")); } catch { /* 結果なし */ }
      resolve({ R, err: err ? String(err.message).slice(0, 200) : "", started: t0, ended: Date.now() });
    });
  p.stdout?.resume(); p.stderr?.on("data", () => {});
});

let failed = 0;
const check = (ok, msg) => { if (!ok) { console.error("FAIL: " + msg); failed++; } };
try {
  // 2 つのウィンドウを同時に動かす（A は長く、B は短く。B が終わったあとも A が使えることを確かめる）
  const [a, b] = await Promise.all([run("A", vA, 9000), run("B", vB, 1500)]);
  if (process.env.VERBOSE) console.log(JSON.stringify({ a, b }, null, 2));
  check(a.R && b.R, "both windows must produce a result: " + JSON.stringify({ a: a.err, b: b.err }));
  if (a.R && b.R) {
    check(a.started < b.ended && b.started < a.ended, "the two windows must overlap in time");
    check(a.R.first.vault === vA && b.R.first.vault === vB, "each window opens its own vault: " + JSON.stringify([a.R.first.vault, b.R.first.vault]));
    check(/アルファ/.test(a.R.first.text) && !/ベータ/.test(a.R.first.text), "window A shows only A's notes: " + a.R.first.text);
    check(/ベータ/.test(b.R.first.text) && !/アルファ/.test(b.R.first.text), "window B shows only B's notes: " + b.R.first.text);
    check(String(a.R.first.bg).toLowerCase() === "#f8f4e8", "window A uses A's own app theme: " + a.R.first.bg);
    check(String(b.R.first.bg).toLowerCase() === "#22272e", "window B uses the default dark (no mixing of settings): " + b.R.first.bg);
    check(/アルファだけの本文/.test(a.R.afterOpen.text) && String(a.R.afterOpen.file).startsWith(vA), "window A still works after B finished (opened A's own note): " + JSON.stringify(a.R.afterOpen).slice(0, 300));
    check(/ベータだけの本文/.test(b.R.afterOpen.text) && String(b.R.afterOpen.file).startsWith(vB), "window B opened B's own note: " + JSON.stringify(b.R.afterOpen).slice(0, 300));
  }
  // どちらの vault のノートも、もう一方の内容に変わっていない
  check(fs.readFileSync(path.join(vA, "n.md"), "utf8").includes("アルファだけの本文") && !fs.readFileSync(path.join(vA, "n.md"), "utf8").includes("ベータ"), "vault A's note is intact");
  check(fs.readFileSync(path.join(vB, "n.md"), "utf8").includes("ベータだけの本文") && !fs.readFileSync(path.join(vB, "n.md"), "utf8").includes("アルファ"), "vault B's note is intact");
  const reg = JSON.parse(fs.readFileSync(path.join(gh, "vaults.json"), "utf8"));
  check(reg.vaults.length === 2, "the registry stays valid: " + JSON.stringify(reg));
  if (failed) process.exit(1);
  console.log("multi e2e: OK (two Electron windows, two Vims, two vaults at the same time; contents / theme / settings are not mixed)");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
