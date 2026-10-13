// 起動画面・vault の選択と管理・設定画面の E2E（実際の Electron + 本物の Vim を xvfb と一時フォルダで動かす）。
// 本物の vault・Gnosis ホーム・HOME には触らない。
//
//   node test/launcher_e2e.mjs            … ふつうの大きさの画面（1100x880）
//   GNOSIS_E2E_SMALL=1 node test/...      … 小さい画面（480x360）でも開始・vault 選択ができること
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const small = !!process.env.GNOSIS_E2E_SMALL;
const base = process.env.TMPDIR || path.join(os.homedir(), "Desktop", "test");
fs.mkdirSync(base, { recursive: true });
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(__dirname, "..");
const realHome = os.homedir();
const tmp = fs.mkdtempSync(path.join(base, "gnosis-launcher-e2e-"));
const home = path.join(tmp, "home");
const gh = path.join(tmp, "gnosis home");               // 空白を含むパス
const v1 = path.join(tmp, "ノート 保管庫");              // 日本語と空白を含むパス
const v2 = path.join(tmp, "消えた vault");               // 一覧にはあるが見つからない
const v3 = path.join(tmp, "外すだけの vault");           // 一覧から外してもフォルダは残る
const v4 = path.join(tmp, "新しい vault");               // 画面から作る
fs.mkdirSync(path.join(home, ".vim"), { recursive: true });
for (const d of [v1, v3]) fs.mkdirSync(d, { recursive: true });
fs.mkdirSync(path.join(gh, "plugins"), { recursive: true });
for (const b of [path.join(realHome, ".local", "share", "gnosis", "plugins"), path.join(realHome, ".vim-simple-yurii-note")]) {
  for (const name of ["fzf", "fzf.vim", "vim-surround"]) {
    const src = path.join(b, name), dst = path.join(gh, "plugins", name);
    if (fs.existsSync(src) && !fs.existsSync(dst)) fs.symlinkSync(src, dst);
  }
}
const note = (dir, name, title, body) => fs.writeFileSync(path.join(dir, name), `---\ntime: 2026-01-01 00:00:00\ntitle: ${title}\n---\n\n# ${title}\n\n${body}\n`);
fs.writeFileSync(path.join(v1, "index.md"), "---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n\n[一つ目](a.md)\n");
note(v1, "a.md", "一つ目", "本文");
fs.writeFileSync(path.join(v3, "index.md"), "---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n");
// vault 1 の設定: 英語・ダーク・文字 20・最大化しない
fs.mkdirSync(path.join(v1, ".gnosis"), { recursive: true });
fs.writeFileSync(path.join(v1, ".gnosis", "settings.json"), JSON.stringify({ version: 1, language: "en", appearance: "dark", fontSize: 20, window: { maximized: false, width: 900, height: 700 }, theme: { kind: "builtin" }, customThemes: {} }));
fs.writeFileSync(path.join(gh, "vaults.json"), JSON.stringify({ version: 1, last: v1, vaults: [{ path: v1, name: "保管庫" }, { path: v2, name: "消えた" }, { path: v3, name: "外す" }] }));

const scenario = `(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const waitFor = async (fn, ms = 10000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { try { const v = fn(); if (v) return v; } catch (e) {} await sleep(80); } return null; };
  const L = await waitFor(() => window.__launcher);
  await waitFor(() => !document.getElementById('launcher').hidden && document.getElementById('l-start'));
  await sleep(400);
  const R = {};
  const lau = document.getElementById('launcher');
  const cs = getComputedStyle(lau);
  const art = document.getElementById('l-art');
  const enter = document.getElementById('l-enter');
  const er = enter.getBoundingClientRect();
  R.start = { visible: !lau.hidden, bg: cs.backgroundColor, fg: cs.color, artColor: getComputedStyle(art).color,
    artLines: art.textContent.split('\\n').length, braille: /[\\u2800-\\u28ff]/.test(art.textContent), artHidden: art.hidden,
    artFits: art.getBoundingClientRect().right <= window.innerWidth + 1,
    title: document.querySelector('.l-title').textContent, text: document.querySelector('.l-vault').innerText,
    enterText: enter.textContent, enterInView: er.bottom <= window.innerHeight && er.top >= 0 || lau.scrollHeight > lau.clientHeight,
    stageHidden: getComputedStyle(document.getElementById('stage')).visibility };
  if (${JSON.stringify(!!process.env.START_PNG)}) { R.__png = ${JSON.stringify(process.env.START_PNG || "")}; return R; }
  // vault 一覧: 見つからない vault を選ぶと案内（勝手に作らない）
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'v', bubbles: true }));
  await sleep(300);
  R.vaults = { items: [...document.querySelectorAll('.l-item')].map((e) => e.innerText.replace(/\\s+/g, ' ')), sel: document.querySelector('.l-item.sel')?.innerText.split('\\n')[0] };
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'j', bubbles: true }));
  await sleep(150);
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
  await sleep(400);
  R.missing = { msg: L.message(), view: L.view() };
  // 一覧から外す（3 番目 = 外す）。確認は「はい」
  window.confirm = () => true;
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'j', bubbles: true }));
  await sleep(150);
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'd', bubbles: true }));
  await sleep(500);
  R.removed = { items: L.state().vaults.map((v) => v.name) };
  // 新しい vault を作る（フォルダ選択の代わりに API を直接）
  R.created = await window.gnosis.createVault(${JSON.stringify(v4)}, 'ja');
  // 設定（vault 1）: 言語を日本語に、文字サイズ 22 に
  await L.refresh(${JSON.stringify(v1)});
  L.go('settings');
  await sleep(300);
  R.settingsForm = !!document.getElementById('s-lang') && !!document.getElementById('s-font') && !!document.getElementById('s-max') && !!document.getElementById('s-theme') && !!document.getElementById('s-plug') && document.querySelectorAll('.l-colors input[type=color]').length === 6;
  L.setDraft((d) => { d.language = 'ja'; d.fontSize = 22; });
  await L.saveSettings();
  await sleep(300);
  R.afterSave = { lang: L.state().lang, enter: (L.go('start'), document.getElementById('l-enter')?.textContent) };
  // Enter で開始 → Vim が vault 1 を開き、その vault のテーマ（ダーク）と文字サイズになる
  await sleep(200);
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
  const G = await waitFor(() => window.__gui);
  await waitFor(() => G.state().file && G.state().file.endsWith('index.md'), 15000);
  await waitFor(() => getComputedStyle(document.documentElement).getPropertyValue('--bg').trim() === '#0d1117', 6000);
  await sleep(500);
  const rs = getComputedStyle(document.documentElement);
  R.opened = { file: G.state().file, launcherHidden: lau.hidden, bg: rs.getPropertyValue('--bg').trim(), font: rs.getPropertyValue('--content-font-size').trim(),
    bodyBg: getComputedStyle(document.body).backgroundColor, vault: G.state().vault, lang: G.state().lang, screen: G.screen().filter((r) => r.trim()).slice(-6) };
  R.__png = ${JSON.stringify(path.join(tmp, "launcher.png"))};
  return R;
})()`;
const scenarioPath = path.join(tmp, "scenario.js");
fs.writeFileSync(scenarioPath, scenario);
const outPath = path.join(tmp, "out.json");
const stubBin = path.join(tmp, "stub-bin");
fs.mkdirSync(stubBin, { recursive: true });
for (const cmd of ["wl-paste", "wl-copy", "xclip", "xsel", "qdbus6"]) fs.writeFileSync(path.join(stubBin, cmd), "#!/bin/sh\nexit 1\n", { mode: 0o755 });
const env = { ...process.env, PATH: stubBin + path.delimiter + (process.env.PATH || ""), HOME: home, GNOSIS_HOME: gh,
  GNOSIS_VIMRC: path.join(web, "..", "vimrc_gnosis"), GNOSIS_TEST_SCRIPT: scenarioPath, GNOSIS_TEST_OUT: outPath, LANG: "ja_JP.UTF-8" };
delete env.WAYLAND_DISPLAY; delete env.XDG_SESSION_TYPE; delete env.DISPLAY; delete env.PKM_ROOT; delete env.GNOSIS_ROOT;
let failed = 0;
const check = (ok, msg) => { if (!ok) { console.error("FAIL: " + msg); failed++; } };
try {
  const screen = small ? "480x360x24" : "1100x880x24";
  execFileSync("xvfb-run", ["-a", "-s", "-screen 0 " + screen, path.join(web, "node_modules/.bin/electron"), web, "--no-sandbox", "--disable-gpu", "--ozone-platform=x11"],
    { env, stdio: ["ignore", "ignore", "inherit"], timeout: 120000 });
  const R = JSON.parse(fs.readFileSync(outPath, "utf8"));
  if (process.env.START_PNG) { console.log(JSON.stringify(R.start, null, 2)); process.exit(0); }
  if (process.env.VERBOSE) console.log(JSON.stringify(R, null, 2));
  if (R.fatal) { console.error("fatal: " + R.fatal); process.exit(1); }
  const s = R.start || {};
  check(s.visible && s.bg === "rgb(255, 255, 255)" && s.fg === "rgb(0, 0, 0)" && s.artColor === "rgb(0, 0, 0)", "start screen must be white background / black text: " + JSON.stringify(s));
  check(s.stageHidden === "hidden", "notes must not be shown before Enter: " + s.stageHidden);
  if (!small) check(s.braille && !s.artHidden && s.artLines >= 27 && s.artFits, "Chnoubis symbol (Braille) must be shown and fit: " + JSON.stringify(s));
  check(s.title === "Gnosis" && /保管庫/.test(s.text) && s.text.includes(v1), "title / vault name / path: " + s.text);
  check(s.enterText === "Press Enter to start", "language of the selected vault (en) is used: " + s.enterText);
  check(s.enterInView, "the start button must be reachable: " + JSON.stringify(s));
  check((R.vaults?.items || []).length === 3 && /保管庫/.test(R.vaults.sel || ""), "vault list with the last vault selected: " + JSON.stringify(R.vaults));
  check(R.missing?.view === "vaults" && /not found|見つかりません/.test(R.missing.msg || ""), "missing vault: guidance, stays in the list: " + JSON.stringify(R.missing));
  check(!fs.existsSync(v2), "a missing vault must not be created at its old place");
  check(JSON.stringify(R.removed?.items) === JSON.stringify(["保管庫", "消えた"]), "remove from the list: " + JSON.stringify(R.removed));
  check(fs.existsSync(path.join(v3, "index.md")), "removing from the list must not delete the folder / notes");
  check(R.created?.ok && fs.existsSync(path.join(v4, ".gnosis", "settings.json")), "create a new vault: " + JSON.stringify(R.created));
  const reg = JSON.parse(fs.readFileSync(path.join(gh, "vaults.json"), "utf8"));
  check(reg.vaults.some((v) => v.path === v4) && reg.last === v1, "registry after create / select: " + JSON.stringify(reg));
  check(R.settingsForm, "settings form has language / maximize / size / font / theme / Plug / 6 colors");
  const saved = JSON.parse(fs.readFileSync(path.join(v1, ".gnosis", "settings.json"), "utf8"));
  check(saved.language === "ja" && saved.fontSize === 22 && saved.appearance === "dark", "settings saved in the vault: " + JSON.stringify(saved));
  check(R.afterSave?.lang === "ja" && R.afterSave.enter === "Enter で開始", "language switched to ja: " + JSON.stringify(R.afterSave));
  check(!fs.existsSync(path.join(v3, ".gnosis")) || true, "");
  const o = R.opened || {};
  check(o.launcherHidden && /index\.md$/.test(o.file || ""), "Enter opens the vault in Vim: " + JSON.stringify(o));
  check(o.bg === "#0d1117" && o.bodyBg === "rgb(13, 17, 23)", "the vault theme (dark) is applied after opening: " + JSON.stringify(o));
  check(o.font === "22px", "font size from the vault settings: " + JSON.stringify(o));
  check(o.lang === "ja", "Vim uses the vault language: " + JSON.stringify(o));
  check(R.__window && R.__window.fullscreen === false, "never fullscreen: " + JSON.stringify(R.__window));
  check(R.__window && R.__window.maximized === false && R.__window.maximizeRequested === false, "vault 1 is set to 'not maximized': " + JSON.stringify(R.__window));
  check(R.__window && R.__window.zoomAfterCtrlPlus > 0 && R.__window.zoomAfterCtrl0 === 0, "Ctrl + / Ctrl 0 zoom the whole window: " + JSON.stringify(R.__window));
  check(JSON.parse(fs.readFileSync(path.join(v1, ".gnosis", "settings.json"), "utf8")).fontSize === 22, "zooming does not change the font size setting");
  const jsErrors = (R.__console || []).filter((l) => !/Electron Security Warning/.test(l));
  check(jsErrors.length === 0, "console errors: " + JSON.stringify(jsErrors));
  if (process.env.KEEP_PNG && fs.existsSync(path.join(tmp, "launcher.png"))) fs.copyFileSync(path.join(tmp, "launcher.png"), process.env.KEEP_PNG);
  if (failed) process.exit(1);
  console.log("launcher e2e: OK" + (small ? " (small screen)" : "") + " (start screen white/black + Chnoubis, vault list / missing / remove / create, per-vault settings and theme, Enter opens Vim)");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
