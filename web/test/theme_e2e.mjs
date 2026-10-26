// 配色（テーマ）の E2E: 実際の Electron + 本物の Vim を xvfb と一時フォルダで動かす。本物の vault・Gnosis ホーム・HOME には触らない。
//   - \A のアプリの既定は白に近い背景（#FAFAFA）・濃い本文（#1F1F1F）。通常の Vim の標準配色（#0C1D32）とは別
//   - 設定画面の配色エディタ: 色を変えると保存前でもプレビューに即時反映（HEX 入力・カラーピッカー・パレット）
//   - キャンセルすると設定ファイルは書き換わらない・保存すると残る・保存後に開き直しても保たれる
//   - アプリ用と通常の Vim 用のテーマは独立（一方を保存してももう一方は変わらない）
//   - プレビューはノートを変更しない
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const base = process.env.TMPDIR || path.join(os.homedir(), "gnosis-work", "test");
fs.mkdirSync(base, { recursive: true });
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(__dirname, "..");
const realHome = os.homedir();
const tmp = fs.mkdtempSync(path.join(base, "gnosis-theme-e2e-"));
const home = path.join(tmp, "home");
const gh = path.join(tmp, "gnosis home");
const v1 = path.join(tmp, "vault 1");
fs.mkdirSync(path.join(home, ".vim"), { recursive: true });
fs.mkdirSync(v1, { recursive: true });
fs.mkdirSync(path.join(gh, "plugins"), { recursive: true });
for (const b of [path.join(realHome, ".local", "share", "gnosis", "plugins"), path.join(realHome, ".vim-simple-yurii-note")]) {
  for (const name of ["fzf", "fzf.vim", "vim-surround"]) {
    const src = path.join(b, name), dst = path.join(gh, "plugins", name);
    if (fs.existsSync(src) && !fs.existsSync(dst)) fs.symlinkSync(src, dst);
  }
}
const indexText = "---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n\n本文のテスト\n";
fs.writeFileSync(path.join(v1, "index.md"), indexText);
fs.mkdirSync(path.join(v1, ".gnosis"), { recursive: true });
const settingsFile = path.join(v1, ".gnosis", "settings.json");
fs.writeFileSync(settingsFile, JSON.stringify({ version: 1, language: "ja", appearance: "dark", fontSize: 16, window: { maximized: false, width: 900, height: 700 }, theme: { kind: "builtin" }, customThemes: {} }));
fs.writeFileSync(path.join(gh, "vaults.json"), JSON.stringify({ version: 1, last: v1, vaults: [{ path: v1, name: "vault1" }] }));
const settingsBefore = fs.readFileSync(settingsFile, "utf8");

const scenario = `(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const waitFor = async (fn, ms = 10000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { try { const v = fn(); if (v) return v; } catch (e) {} await sleep(80); } return null; };
  const L = await waitFor(() => window.__launcher);
  await waitFor(() => !document.getElementById('launcher').hidden && document.getElementById('l-start'));
  await sleep(300);
  const R = {};
  const rgb = (el) => getComputedStyle(el).backgroundColor;
  const fgc = (el) => getComputedStyle(el).color;
  const fire = (el, type) => el.dispatchEvent(new Event(type, { bubbles: true }));
  // ---- 設定画面: アプリ用の配色エディタを開く（既定は白）
  L.go('settings');
  await sleep(300);
  R.form = { vimBtn: !!document.getElementById('s-vim-custom'), appBtn: !!document.getElementById('s-app-custom'), appSel: document.getElementById('s-app-theme')?.value,
    appOptions: [...document.querySelectorAll('#s-app-theme option')].map((o) => o.textContent) };
  document.getElementById('s-app-custom').click();
  await sleep(400);
  const pv = document.getElementById('e-preview');
  R.editor = { open: !!pv, title: document.querySelector('.l-editor h2')?.textContent, rows: document.querySelectorAll('.e-row').length,
    pickers: document.querySelectorAll('.e-row input[type=color]').length, hexes: [...document.querySelectorAll('.e-hex')].map((e) => e.value),
    palette: document.querySelectorAll('.e-sw').length, previewBg: pv && rgb(pv), previewFg: pv && fgc(pv),
    link: pv && { color: fgc(pv.querySelector('a')), underline: getComputedStyle(pv.querySelector('a')).textDecorationLine },
    heading: pv && { color: fgc(pv.querySelector('.pv-h')), weight: getComputedStyle(pv.querySelector('.pv-h')).fontWeight },
    text: pv && pv.innerText, contrast: document.getElementById('e-contrast')?.innerText };
  // ---- 色を変える: カラーピッカー（input イベント）で背景を変えると、保存前でもプレビューが即座に変わる
  const cbg = document.getElementById('e-c-bg');
  cbg.value = '#102030'; fire(cbg, 'input');
  await sleep(100);
  R.picker = { previewBg: rgb(pv), hex: document.getElementById('e-h-bg').value };
  // ---- HEX を直接入力
  const hlink = document.getElementById('e-h-link');
  hlink.focus(); hlink.value = '#c0ffee'; fire(hlink, 'input');
  await sleep(100);
  R.hex = { linkColor: fgc(pv.querySelector('a')), picker: document.getElementById('e-c-link').value };
  const hhead = document.getElementById('e-h-heading');
  hhead.focus(); hhead.value = 'f80'; fire(hhead, 'input');   // 3 桁
  await sleep(100);
  R.hex3 = { headingColor: fgc(pv.querySelector('.pv-h')) };
  hhead.value = 'zzz'; fire(hhead, 'input');                   // 不正な HEX は反映しない
  await sleep(100);
  R.hexBad = { headingColor: fgc(pv.querySelector('.pv-h')) };
  // ---- パレットから選ぶ（今の行 = 見出し）
  document.getElementById('e-pal-1-6').click();
  await sleep(100);
  R.palette = { headingColor: fgc(pv.querySelector('.pv-h')), hex: document.getElementById('e-h-heading').value };
  // ---- 選択状態・カーソル行
  const hsel = document.getElementById('e-h-selection');
  hsel.focus(); hsel.value = '#335577'; fire(hsel, 'input');
  const hcur = document.getElementById('e-h-cursorline');
  hcur.focus(); hcur.value = '#112244'; fire(hcur, 'input');
  await sleep(100);
  R.selcur = { sel: rgb(pv.querySelector('.pv-sel')), cur: rgb(pv.querySelector('.pv-cur')) };
  // ---- ここまでは保存していない: 設定ファイルは変わらない（確認は Node 側）
  R.beforeCancel = true;
  document.getElementById('e-cancel').click();
  await sleep(400);
  R.afterCancel = { view: L.view(), editorGone: !document.getElementById('e-preview'), appSel: document.getElementById('s-app-theme')?.value };
  // ---- もう一度開いて、保存する
  document.getElementById('s-app-custom').click();
  await sleep(400);
  R.reopen = { previewBg: rgb(document.getElementById('e-preview')) };   // 取り消したあとは元（白）から始まる
  const cbg2 = document.getElementById('e-c-bg');
  cbg2.value = '#f8f4e8'; fire(cbg2, 'input');
  document.getElementById('e-name').value = 'ほんのり黄色';
  await sleep(100);
  document.getElementById('e-save').click();
  await sleep(700);
  R.saved = { view: L.view(), appSel: document.getElementById('s-app-theme')?.value, st: L.state().settings.appTheme };
  // ---- 通常の Vim 側のエディタ（選んでいるテーマの色から始まる = 標準の紺）
  document.getElementById('s-vim-custom').click();
  await sleep(400);
  R.vimEditor = { title: document.querySelector('.l-editor h2')?.textContent, previewBg: rgb(document.getElementById('e-preview')) };
  document.getElementById('e-cancel').click();
  await sleep(300);
  // ---- Esc キーでもキャンセルできる
  document.getElementById('s-vim-custom').click();
  await sleep(300);
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  await sleep(300);
  R.escCancel = { view: L.view(), editorGone: !document.getElementById('e-preview') };
  // ---- ↑ ↓ で項目を移動できる（設定画面）
  document.getElementById('s-lang').focus();
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
  R.arrow = { tagAfterDown: document.activeElement.tagName, idAfterDown: document.activeElement.id };
  // ---- 保存した vault を開く: アプリ用の配色（保存したもの）が画面に出る
  L.go('start');
  await sleep(200);
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
  const G = await waitFor(() => window.__gui);
  await waitFor(() => G.state().file && G.state().file.endsWith('index.md'), 15000);
  await waitFor(() => getComputedStyle(document.documentElement).getPropertyValue('--bg').trim().toLowerCase() === '#f8f4e8', 8000);
  await sleep(500);
  const rs = getComputedStyle(document.documentElement);
  R.opened = { bg: rs.getPropertyValue('--bg').trim(), fg: rs.getPropertyValue('--fg').trim(), bodyBg: rgb(document.body), palette: G.state().palette && G.state().palette.bg };
  R.__png = ${JSON.stringify(path.join(tmp, "theme.png"))};
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
  execFileSync("xvfb-run", ["-a", "-s", "-screen 0 1280x1000x24", path.join(web, "node_modules/.bin/electron"), web, "--no-sandbox", "--disable-gpu", "--ozone-platform=x11"],
    { env, stdio: ["ignore", "ignore", "inherit"], timeout: 120000 });
  const R = JSON.parse(fs.readFileSync(outPath, "utf8"));
  if (process.env.VERBOSE) console.log(JSON.stringify(R, null, 2));
  if (R.fatal) { console.error("fatal: " + R.fatal); process.exit(1); }
  const e = R.editor || {};
  check(R.form?.vimBtn && R.form?.appBtn && R.form?.appSel === "builtin" && R.form.appOptions.length === 1, "settings: both color editors, app theme select defaults to builtin: " + JSON.stringify(R.form));
  check(e.open && e.rows === 8 && e.pickers === 8 && e.hexes.length === 8 && e.palette === 72, "editor: 8 colors with picker + HEX, 8x9 palette: " + JSON.stringify(e));
  check(/アプリ/.test(e.title || ""), "editor title says app: " + e.title);
  check(e.previewBg === "rgb(250, 250, 250)" && e.previewFg === "rgb(31, 31, 31)", "app editor starts from the builtin light colors (#FAFAFA/#1F1F1F): " + JSON.stringify({ bg: e.previewBg, fg: e.previewFg }));
  check(e.hexes[0].toLowerCase() === "#fafafa" && e.hexes[1].toLowerCase() === "#1f1f1f", "HEX codes are shown: " + JSON.stringify(e.hexes));
  check(e.link?.underline === "underline" && e.link.color !== e.previewFg, "preview: link is underlined and differs from the text: " + JSON.stringify(e.link));
  check(e.heading?.weight >= 700 && e.heading.color !== e.previewFg, "preview: heading is bold and differs from the text: " + JSON.stringify(e.heading));
  check(/植物について/.test(e.text) && /ローズマリー/.test(e.text) && /レモンバーム/.test(e.text) && /ChildBranch/.test(e.text) && !/example\.md/.test(e.text), "preview: Japanese sample with link names only: " + e.text);
  check(/:\s*1/.test(e.contrast || ""), "contrast ratios are shown: " + e.contrast);
  check(R.picker?.previewBg === "rgb(16, 32, 48)" && R.picker.hex.toLowerCase() === "#102030", "color picker input updates the preview at once: " + JSON.stringify(R.picker));
  check(R.hex?.linkColor === "rgb(192, 255, 238)" && R.hex.picker === "#c0ffee", "typing a HEX updates the preview (and the picker): " + JSON.stringify(R.hex));
  check(R.hex3?.headingColor === "rgb(255, 136, 0)", "3-digit HEX is accepted: " + JSON.stringify(R.hex3));
  check(R.hexBad?.headingColor === "rgb(255, 136, 0)", "an invalid HEX is not applied: " + JSON.stringify(R.hexBad));
  check(R.palette?.hex && R.palette.hex !== "#ff8800" && R.palette.headingColor !== "rgb(255, 136, 0)", "choosing from the palette changes the selected color: " + JSON.stringify(R.palette));
  check(R.selcur?.sel === "rgb(51, 85, 119)" && R.selcur.cur === "rgb(17, 34, 68)", "selection / cursor line preview: " + JSON.stringify(R.selcur));
  check(R.afterCancel?.view === "settings" && R.afterCancel.editorGone && R.afterCancel.appSel === "builtin", "cancel returns to settings without applying: " + JSON.stringify(R.afterCancel));
  check(R.reopen?.previewBg === "rgb(250, 250, 250)", "after cancel the editor starts from the old colors again: " + JSON.stringify(R.reopen));
  check(R.saved?.view === "settings" && R.saved.st?.kind === "custom" && R.saved.st.name === "ほんのり黄色", "saving selects the new app theme: " + JSON.stringify(R.saved));
  check(/アプリ|app/i.test(R.vimEditor?.title || "") === false && R.vimEditor?.previewBg === "rgb(30, 30, 30)", "regular Vim editor starts from the standard dark (#1E1E1E), not the app colors: " + JSON.stringify(R.vimEditor));
  check(R.escCancel?.view === "settings" && R.escCancel.editorGone, "Esc cancels the editor: " + JSON.stringify(R.escCancel));
  check(R.arrow?.idAfterDown && R.arrow.idAfterDown !== "s-lang", "ArrowDown moves between settings items: " + JSON.stringify(R.arrow));
  // 設定ファイル: アプリ用だけが保存され、通常の Vim 用は変わらない・キャンセルした分は残らない
  const saved = JSON.parse(fs.readFileSync(settingsFile, "utf8"));
  check(saved.appTheme?.kind === "custom" && saved.appTheme.name === "ほんのり黄色" && saved.appCustomThemes["ほんのり黄色"]?.bg === "#f8f4e8", "settings.json has the saved app theme: " + JSON.stringify(saved));
  check(saved.theme?.kind === "builtin" && Object.keys(saved.customThemes || {}).length === 0, "saving the app theme does not touch the regular Vim theme: " + JSON.stringify(saved));
  check(Object.keys(saved.appCustomThemes).length === 1, "the cancelled colors were not saved: " + JSON.stringify(saved.appCustomThemes));
  check(fs.readFileSync(path.join(v1, "index.md"), "utf8").startsWith(indexText.split("\n")[0]) && fs.readFileSync(path.join(v1, "index.md"), "utf8").includes("本文のテスト"), "the notes are not changed by previewing / saving a theme");
  const o = R.opened || {};
  check(o.bg?.toLowerCase() === "#f8f4e8" && o.bodyBg === "rgb(248, 244, 232)" && o.palette?.toLowerCase() === "#f8f4e8", "after opening the vault the saved app theme is applied: " + JSON.stringify(o));
  const jsErrors = (R.__console || []).filter((l) => !/Electron Security Warning/.test(l));
  check(jsErrors.length === 0, "console errors: " + JSON.stringify(jsErrors));
  if (process.env.KEEP_PNG && fs.existsSync(path.join(tmp, "theme.png"))) fs.copyFileSync(path.join(tmp, "theme.png"), process.env.KEEP_PNG);
  if (failed) process.exit(1);
  console.log("theme e2e: OK (app default white, live preview via picker / HEX / palette, cancel keeps the old colors, save per vault, app and Vim themes are independent)");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
