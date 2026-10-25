// 画面側。Vim（本体）の状態を、マークダウンの見た目で映し、端末の画面は必要なときだけ見せる。
// 2026-10-24 に作り直して小さくした: ボタン・タブ・分割・コマンドパレット・GUI 編集・閲覧専用モードは無い（Vim にある操作だけ）。
// あるのは 起動画面（vault の選択）・マークダウンの表示・曼荼羅（アプリ専用の描き方）・端末（Vim の画面）・下のバー。
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { createView } from "./view.js";
import { showLauncher } from "./launcher.js";
import { createMandala } from "./mandala.js";
import { createScan } from "./scan.js";

const gui = window.gui;
const $ = (id) => document.getElementById(id);

const STRIP_ROWS = 2; // 普段は端末の下の 2 行（ステータス行・コマンド行/メッセージ）だけ見せる
let term = null;
let fit = null;
let view = null;
let mandala = null;
let scan = null;
let scanReq = 0;
let cell = { w: 8, h: 18 };
let last = { file: "", mode: "n", bt: "", popups: 0, mod: 0, cmdtype: "" };
let expanded = false;
let collapseTimer = null;

// ---------------------------------------------------------------- 端末（xterm.js）

function layoutTerm() {
  // 端末全体の高さは変えず（Vim の画面の大きさを保つ）、見える範囲だけを切り替える
  $("term").style.height = cell.h * term.rows + "px";
  document.documentElement.style.setProperty("--strip-h", cell.h * STRIP_ROWS + "px");
}

function measureCell() {
  const screen = term.element?.querySelector(".xterm-screen");
  if (screen && term.rows && term.cols) cell = { w: screen.clientWidth / term.cols, h: screen.clientHeight / term.rows };
}

function fitTerm() {
  // 測るときは端末全体を見せる
  const wrap = $("termwrap");
  const was = wrap.classList.contains("expanded");
  wrap.classList.add("expanded");
  $("term").style.height = "100%";
  const dim = fit.proposeDimensions();
  if (dim && dim.cols > 10 && dim.rows > 3 && (dim.cols !== term.cols || dim.rows !== term.rows)) term.resize(dim.cols, dim.rows);
  measureCell();
  layoutTerm();
  if (!was) wrap.classList.remove("expanded");
  return { cols: term.cols, rows: term.rows };
}

function setExpanded(on) {
  if (on === expanded) return;
  expanded = on;
  $("termwrap").classList.toggle("expanded", on);
  $("termwrap").classList.toggle("strip", !on);
  if (!on) $("termwrap").style.clipPath = "";
  term.focus();
}

// 端末の全面表示のうち、ポップアップの長方形だけを見せる（背景は下の表示のまま）
function applyOverlay(s) {
  const wrap = $("termwrap");
  const scr = document.querySelector("#term .xterm-screen");
  if (!expanded || !scr || !overlayOnly(s)) { wrap.style.clipPath = ""; return; }
  const sr = scr.getBoundingClientRect();
  const wr = wrap.getBoundingClientRect();
  const cw = sr.width / term.cols;
  const ch = sr.height / term.rows;
  const ox = sr.left - wr.left;
  const oy = sr.top - wr.top;
  const parts = s.popuppos.map(([col, line, w, h]) => {
    const x = Math.max(0, ox + (col - 1) * cw - 1), y = Math.max(0, oy + (line - 1) * ch - 1);
    return `M${x} ${y}h${w * cw + 2}v${h * ch + 2}h${-(w * cw + 2)}z`;
  });
  wrap.style.clipPath = `path('${parts.join("")}')`;
}

// ポップアップ（検索など）だけが理由のときは、背景を変えず、ポップアップの場所にだけ端末を重ねる
function overlayOnly(s) {
  const m = (s.mode || "n")[0];
  return (s.popuppos || []).length > 0 && m !== "r" && m !== "!" && s.mode !== "rm";
}

// 端末の画面そのものが要る場面（確認・fzf・ポップアップ・Enter 待ちなど）か
function needsTerminal(s) {
  const m = (s.mode || "n")[0];
  return s.bt === "terminal" || m === "t" || m === "r" || m === "!" || (s.popups || 0) > 0 || s.mode === "rm";
}

// ---------------------------------------------------------------- 状態の反映

const MODE_LABEL = { n: "NORMAL", i: "INSERT", v: "VISUAL", V: "V-LINE", "\x16": "V-BLOCK", R: "REPLACE", c: "COMMAND", t: "TERMINAL", r: "PROMPT", s: "SELECT", S: "S-LINE", "\x13": "S-BLOCK", "!": "SHELL" };
const MODE_CLASS = { n: "normal", i: "insert", v: "visual", V: "visual", "\x16": "visual", R: "replace", c: "command", t: "command", r: "command", s: "visual", S: "visual", "\x13": "visual", "!": "command" };

// 配色（vault の設定のテーマ。Vim が読み込んだ色）と文字サイズを画面に反映する
let lastLook = "";
function applyLook(s) {
  if (!s.palette && !s.fontSize) return;
  const key = JSON.stringify([s.palette, s.fontSize]);
  if (key === lastLook) return;
  lastLook = key;
  const p = s.palette && s.palette.bg ? s.palette : null;
  const r = document.documentElement.style;
  if (p) {
    const dark = p.base === "dark";
    r.setProperty("--bg", p.bg);
    r.setProperty("--fg", p.fg);
    r.setProperty("--link", p.link);
    r.setProperty("--accent", p.link);
    r.setProperty("--heading", p.heading);
    r.setProperty("--subheading", p.subheading || p.heading);
    r.setProperty("--selection", p.selection);
    r.setProperty("--cursorline", p.cursorline);
    r.setProperty("--bg-2", `color-mix(in srgb, ${p.fg} ${dark ? 8 : 4}%, ${p.bg})`);
    r.setProperty("--bg-3", `color-mix(in srgb, ${p.fg} ${dark ? 14 : 8}%, ${p.bg})`);
    r.setProperty("--fg-dim", `color-mix(in srgb, ${p.fg} 62%, ${p.bg})`);
    r.setProperty("--line", `color-mix(in srgb, ${p.fg} ${dark ? 22 : 18}%, ${p.bg})`);
    document.documentElement.style.colorScheme = dark ? "dark" : "light";
    // ライトのときだけ、Markdown Viewer 拡張（GitHub スタイル）の見え方にする（styles.css の html.theme-light）
    document.documentElement.classList.toggle("theme-light", !dark);
    document.documentElement.classList.toggle("theme-dark", dark);
    if (term) term.options.theme = { background: p.bg, foreground: p.fg, cursor: p.fg, cursorAccent: p.bg, selectionBackground: p.selection };
  }
  if (s.fontSize) {
    r.setProperty("--content-font-size", s.fontSize + "px");
    if (term && term.options.fontSize !== Math.max(10, s.fontSize - 2)) {
      term.options.fontSize = Math.max(10, s.fontSize - 2);
      setTimeout(() => { const d = fitTerm(); gui.resize(d.cols, d.rows); }, 0);
    }
  }
  view?.refresh?.();
  mandala?.rerender?.();
}

function applyState(s) {
  applyLook(s);
  // \F: 紙のスキャンの番号付け画面を開く（Vim が合図の番号を増やす）
  if (typeof s.scanReq === "number") {
    if (s.scanReq > scanReq && scan && !scan.isOpen()) scan.open();
    scanReq = s.scanReq;
  }
  last = { ...last, ...s, lines: undefined };
  const m = (s.mode || "n")[0];
  const md = s.mandala && s.mandala.cells ? s.mandala : null;
  const mEl = $("mode");
  mEl.textContent = (md && s.focus === "mandala" && m === "n") ? "MANDALA" : (MODE_LABEL[m] || String(s.mode).toUpperCase());
  if (last.copyStack) mEl.textContent += " · COPY STACK";
  mEl.className = "mode " + (MODE_CLASS[m] || "normal");
  $("file").textContent = s.file ? s.file.split("/").pop() : "";
  $("dirty").textContent = s.mod ? "●" : "";

  // 端末の画面が要るときだけ広げる（戻すときは少し待って、ちらつきを防ぐ）
  if (needsTerminal(s)) {
    clearTimeout(collapseTimer);
    collapseTimer = null;
    setExpanded(true);
  } else if (expanded && !collapseTimer) {
    collapseTimer = setTimeout(() => { collapseTimer = null; if (!needsTerminal(last)) setExpanded(false); }, 120);
  }
  applyOverlay(last);

  // 曼荼羅: 開いていれば左（全画面 9×9 で右の窓が無いときは全面）に描く
  const hasNote = !!(s.file) && s.bt === "";
  $("mandala").hidden = !md;
  $("main").classList.toggle("with-mandala", !!md);
  $("main").classList.toggle("mandala-only", !!md && !hasNote);
  $("view").hidden = !!md && !hasNote;
  if (md) {
    // 曼荼羅の窓の幅（Vim の桁数）の割合で、アプリの曼荼羅の幅を合わせる（< > で動く）
    $("mandala").style.flexBasis = md.wcols && s.cols && hasNote ? (100 * md.wcols / s.cols).toFixed(2) + "%" : "";
    mandala.render(md);
  }

  // ノート（曼荼羅が開いていれば、右の窓のノート）の内容とカーソルをマークダウンで映す
  if (s.bt === "terminal" || !hasNote) return;
  view.setLinkSource(!!last.linkSource);
  view.setHideImage(!!last.hideImage);
  view.setLinkEdit(!!last.linkEdit);
  if (s.lines) { view.setText(s.lines.join("\n")); view.setHide(s.hide || []); preloadImages(s.lines); }
  if (s.vtext) view.setVtext(s.vtext);
  if (s.cur) view.setVim({ cur: s.cur, mode: md && s.focus === "mandala" ? "n" : (s.mode || "n"), vis: s.vis });
}

// ペインの大きさが変わったら、Vim の端末の大きさを合わせ直す
let fitTimer = null;
function scheduleFit() {
  clearTimeout(fitTimer);
  fitTimer = setTimeout(() => {
    const st = $("stage");
    if (!term || !st || st.offsetWidth < 50 || st.offsetHeight < 50) return;
    const d = fitTerm();
    gui.resize(d.cols, d.rows);
    view?.refresh?.();
  }, 60);
}

// ---------------------------------------------------------------- 画像

// 読み込んだ画像を覚える。key は「ノートのあるフォルダ + 書かれたパス」
const imgCache = new Map(); // key -> { url, w, h }
const imgPending = new Map(); // key -> Promise<url|null>
const IMG_CACHE_MAX = 300;

function imgKey(file, src) {
  const i = (file || "").lastIndexOf("/");
  return (i < 0 ? "" : file.slice(0, i)) + "/" + src;
}

function imageURL(src, fileOverride) {
  if (/^[a-z]+:\/\//i.test(src) || src.startsWith("data:")) return src;
  const file = fileOverride || last.file;
  const key = imgKey(file, src);
  const c = imgCache.get(key);
  if (c && c.url) return c.url;
  if (imgPending.has(key)) return imgPending.get(key);
  const p = (async () => {
    const bytes = await gui.readImage(file, src);
    if (!bytes) return null;
    const url = URL.createObjectURL(new Blob([bytes]));
    imgCache.set(key, { ...(imgCache.get(key) || {}), url });
    if (imgCache.size > IMG_CACHE_MAX) {
      const oldest = imgCache.keys().next().value;
      const o = imgCache.get(oldest);
      if (o && o.url) URL.revokeObjectURL(o.url);
      imgCache.delete(oldest);
    }
    return url;
  })().finally(() => imgPending.delete(key));
  imgPending.set(key, p);
  return p;
}

function imageSize(src) {
  const c = imgCache.get(imgKey(last.file, src));
  return c && c.w ? { w: c.w, h: c.h } : null;
}

function onImageSize(src, w, h, fileOverride) {
  if (!w || !h) return;
  const key = imgKey(fileOverride || last.file, src);
  imgCache.set(key, { ...(imgCache.get(key) || {}), w, h });
}

// ノートを開いたとき、中の画像を先に読んで大きさを調べる（スクロールしても全体の長さが跳ばない）
let preloadTimer = null;
const PRELOAD_MAX = 24;
const PRELOAD_PARALLEL = 4;
function preloadImages(lines) {
  const file = last.file;
  const re = /!\[(?:\\.|[^\]\\])*\]\(([^)\s]+)(?:\s+"[^"]*")?\)|<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["'][^>]*>/gi;
  const seen = new Set();
  const queue = [];
  for (const ln of lines) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(ln)) !== null) {
      const src = m[1] || m[2];
      if (/^[a-z]+:\/\//i.test(src) || src.startsWith("data:") || seen.has(src)) continue;
      seen.add(src);
      const c = imgCache.get(imgKey(file, src));
      if (!(c && c.w) && queue.length < PRELOAD_MAX) queue.push(src);
    }
  }
  if (!queue.length) return 0;
  let active = 0;
  const finish = () => {
    clearTimeout(preloadTimer);
    preloadTimer = setTimeout(() => { if (last.file === file) view.refresh(); }, 120);
  };
  const pump = () => {
    while (active < PRELOAD_PARALLEL && queue.length) {
      const src = queue.shift();
      active++;
      Promise.resolve(imageURL(src, file)).then((url) => new Promise((resolve) => {
        if (!url) return resolve();
        const im = new Image();
        im.onload = () => { onImageSize(src, im.naturalWidth, im.naturalHeight, file); resolve(); };
        im.onerror = () => resolve();
        im.src = url;
      })).catch(() => {}).finally(() => { active--; if (queue.length) pump(); else if (!active) finish(); });
    }
  };
  pump();
  return queue.length;
}

// ---------------------------------------------------------------- マウス

// 表示をクリックしたとき、Vim のカーソルをそこへ動かす。リンクならそのまま開く（Enter）。Alt + クリックはカーソルだけ。
function onClick({ pos, link, alt }) {
  if (pos == null) return;
  if (alt) link = false;
  const [l, c] = view.lineColAt(pos);
  const m = (last.mode || "n")[0];
  // 曼荼羅が開いているときは、まず右のノートの窓へ移る（Vim の窓の移動）
  const toNote = last.mandala && last.mandala.cells && last.focus === "mandala" && last.mandala.noteWin > 0
    ? `call win_gotoid(${last.mandala.noteWin})|` : "";
  // 打った :call … が下の行に残らないよう、直後に redraw して空のメッセージで消す
  const mv = `:${toNote}call cursor(${l},${c})|redraw|echo ""\r`;
  if (m === "n") gui.write(mv + (link ? "\r" : ""));
  else if (m === "i") gui.write("\x0f" + mv);
}

// 曼荼羅のマスのクリック（enter が真なら中心にする）
function onMandalaCell(r, c, enter) {
  gui.write(`\x1b:call gnosis#mview#gui_click(${r},${c},${enter ? 1 : 0})|redraw|echo ""\r`);
}

// 画面側のエラーを、下のバーに赤く出す（何が起きたか分かるように）。ログにも残る（main 側）。
function showError(msg) {
  const el = $("err");
  if (!el) return;
  el.textContent = (document.documentElement.lang === "en" ? "Error: " : "エラー: ") + String(msg).slice(0, 160);
  el.hidden = false;
  clearTimeout(showError._t);
  showError._t = setTimeout(() => { el.hidden = true; }, 12000);
}

// ---------------------------------------------------------------- 起動

// 紙のスキャンの番号付けだけの窓（Vim の \F から。Vim も端末も起動しない）
async function bootScanOnly() {
  document.body.classList.remove("launching");
  $("stage").hidden = true;
  $("statusbar").hidden = true;
  $("launcher").hidden = true;
  scan = createScan($("scan"), {
    api: { run: (cmd, args) => gui.scan(cmd, args), image: (n) => gui.scanImage(n), ls: (d) => gui.scanLs(d) },
    onClose: () => gui.quit(),
  });
  window.__gui = { scan, state: () => ({}) };
  await scan.open();
}

async function boot() {
  if (new URLSearchParams(location.search).get("scan") === "1") return bootScanOnly();
  window.addEventListener("error", (e) => showError(e.message || e.error));
  window.addEventListener("unhandledrejection", (e) => showError(e.reason && e.reason.message || e.reason));
  view = createView({ parent: $("view"), getImageURL: imageURL, getImageSize: imageSize, onImageSize, onClick });
  mandala = createMandala($("mandala"), { onCell: onMandalaCell });
  scan = createScan($("scan"), {
    api: { run: (cmd, args) => gui.scan(cmd, args), image: (n) => gui.scanImage(n), ls: (d) => gui.scanLs(d) },
    // 終わったら Vim にファイルの更新を読ませ、キー入力を端末へ戻す
    onClose: (changed) => { if (changed) gui.write("\x1b:checktime|redraw\r"); term.focus(); },
  });

  term = new Terminal({
    fontFamily: '"JetBrains Mono", "Noto Sans Mono CJK JP", ui-monospace, monospace',
    fontSize: 14,
    cursorBlink: false,
    allowProposedApi: true,
    scrollback: 0,
    theme: { background: "#fafafa", foreground: "#1f1f1f", cursor: "#1f1f1f", cursorAccent: "#fafafa", selectionBackground: "#b5cfee" },
  });
  fit = new FitAddon();
  term.loadAddon(fit);
  term.open($("term"));
  try { await document.fonts.ready; } catch { /* ignore */ }

  term.onData((d) => gui.write(d));
  gui.onData((d) => term.write(d));
  gui.onState((s) => { try { applyState(s); } catch (e) { console.error("applyState failed: " + (e && e.stack || e)); showError(e && e.message || e); } });
  gui.onExit(() => { $("mode").textContent = "EXIT"; });

  // 起動画面で vault を選んで Enter を押したら（GNOSIS_ROOT 指定のときはすぐ）Vim を起動する
  await showLauncher((vaultPath, settings) => {
    applyLook({ palette: null, fontSize: settings && settings.fontSize });
    const { cols, rows } = fitTerm();
    gui.start(cols, rows, vaultPath);
    term.focus();
    scheduleFit();
  });

  window.addEventListener("resize", () => { scheduleFit(); });
  // どこを押しても、キー入力は端末（Vim）へ戻す
  const backToInput = () => { if (document.getElementById("launcher").hidden && !(scan && scan.isOpen())) term.focus(); };
  document.addEventListener("mousedown", () => setTimeout(backToInput, 0));
  window.addEventListener("focus", backToInput);

  // デバッグ・テスト用フック
  window.__gui = {
    term, view, mandala,
    state: () => last,
    send: (d) => gui.write(d),
    isExpanded: () => expanded,
    screen: () => {
      const b = term.buffer.active;
      const out = [];
      for (let i = 0; i < term.rows; i++) out.push(b.getLine(i)?.translateToString(true) ?? "");
      return out;
    },
  };
}

document.addEventListener("DOMContentLoaded", boot);
