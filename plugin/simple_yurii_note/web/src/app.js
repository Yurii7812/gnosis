// 画面側。Vim（本体）の状態を、マークダウンの見た目で映し、端末の画面は必要なときだけ見せる。
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { createView } from "./view.js";

const gui = window.gui;
const $ = (id) => document.getElementById(id);

const STRIP_ROWS = 3; // 普段は端末の下の 3 行（ステータス行・コマンド行・メッセージ）だけ見せる
let term = null;
let fit = null;
let view = null;
let cell = { w: 8, h: 18 };
let last = { file: "", mode: "n", bt: "", popups: 0, mod: 0, cmdtype: "" };
let expanded = false;
let collapseTimer = null;

// ---------------------------------------------------------------- 端末（xterm.js）

function fullRowsPx() { return cell.h * term.rows; }

function layoutTerm() {
  // 端末全体の高さは変えず（Vim の画面の大きさを保つ）、見える範囲だけを切り替える
  $("term").style.height = fullRowsPx() + "px";
  const stripH = cell.h * STRIP_ROWS;
  document.documentElement.style.setProperty("--strip-h", stripH + "px");
}

function measureCell() {
  const screen = term.element?.querySelector(".xterm-screen");
  if (screen && term.rows && term.cols) {
    cell = { w: screen.clientWidth / term.cols, h: screen.clientHeight / term.rows };
  }
}

function fitTerm() {
  // 測るときは端末全体を見せる
  const wrap = $("termwrap");
  const was = wrap.classList.contains("expanded");
  wrap.classList.add("expanded");
  $("term").style.height = "100%";
  const dim = fit.proposeDimensions();
  if (dim && dim.cols > 10 && dim.rows > 3) {
    if (dim.cols !== term.cols || dim.rows !== term.rows) term.resize(dim.cols, dim.rows);
  }
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
  term.focus();
}

// 端末の画面そのものが要る場面（確認・fzf・ポップアップ・Enter 待ちなど）か
function needsTerminal(s) {
  const m = (s.mode || "n")[0];
  return s.bt === "terminal" || m === "t" || m === "r" || m === "!" || (s.popups || 0) > 0 || s.mode === "rm";
}

// ---------------------------------------------------------------- 状態の反映

const MODE_LABEL = { n: "NORMAL", i: "INSERT", v: "VISUAL", V: "V-LINE", "\x16": "V-BLOCK", R: "REPLACE", c: "COMMAND", t: "TERMINAL", r: "PROMPT", s: "SELECT", S: "S-LINE", "\x13": "S-BLOCK", "!": "SHELL" };
const MODE_CLASS = { n: "normal", i: "insert", v: "visual", V: "visual", "\x16": "visual", R: "replace", c: "command", t: "command", r: "command", s: "visual", S: "visual", "\x13": "visual", "!": "command" };

function applyState(s) {
  last = { ...last, ...s, lines: undefined };
  const m = (s.mode || "n")[0];
  const el = $("mode");
  const showView = viewOnly && !needsTerminal(s);
  el.textContent = showView ? "VIEW" : (MODE_LABEL[m] || String(s.mode).toUpperCase());
  el.className = "mode " + (showView ? "viewonly" : (MODE_CLASS[m] || "normal"));
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

  // バッファの内容とカーソルをマークダウンで映す（端末バッファは映さない）
  if (s.bt === "terminal") return;
  const fileChanged = viewOnly && s.file && s.file !== lastViewFile;
  if (s.file) lastViewFile = s.file;
  if (s.lines) { view.setText(s.lines.join("\n")); preloadImages(s.lines); }
  if (fileChanged) view.view.scrollDOM.scrollTop = 0; // 見るだけのときは別のノートに移ったら先頭から
  if (s.vtext) view.setVtext(s.vtext);
  if (s.cur) view.setVim({ cur: s.cur, mode: s.mode || "n", vis: s.vis });
}

// ---------------------------------------------------------------- 起動

// 読み込んだ画像を覚える。key は「ノートのあるフォルダ + 書かれたパス」。
// 画面から外れたウィジェットが作り直されても、読み直さず（Blob を作り直さず）すぐ表示できる。
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
  if (c && c.url) return c.url; // すぐ表示（同期）
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

// ノートを開いたとき、中の画像を先に読んで大きさを調べる。まだ画面に出ていない画像も高さが
// 正確になり、スクロールしても全体の長さが跳ばない（初めて見る画像でも消えたり跳んだりしない）。
let preloadTimer = null;
const PRELOAD_MAX = 24; // 1 ノートで先に調べる画像の上限
const PRELOAD_PARALLEL = 4; // 同時に読む数
function preloadImages(lines) {
  const file = last.file;
  const re = /!\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)|<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["'][^>]*>/gi;
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

// ---------------------------------------------------------------- 見るだけモード
// F2 で「見るだけ」と「普通の Vim」を切り替える。見るだけのときは、カーソルを出さず、
// キーを Vim に送らない（ノートは絶対に変わらない）。j/k・矢印・Space・PageUp/Down・gg/G・
// Ctrl-d/u でスクロールし、リンクはクリックで開く。確認・fzf などの端末が要る場面では、
// 普通どおりキーを Vim へ送る。
let viewOnly = false;
let lastViewFile = "";
let gPending = false;

function setViewOnly(on) {
  viewOnly = !!on;
  $("view").classList.toggle("view-only", viewOnly);
  view.setViewOnly(viewOnly);
  if (!viewOnly) view.setVim({ cur: last.cur || [1, 1], mode: last.mode || "n", vis: last.vis }); // カーソルへ戻す
  applyState({ mode: last.mode, file: last.file, bt: last.bt, popups: last.popups });
}

function viewOnlyKey(e) {
  const sc = view.view.scrollDOM;
  const page = sc.clientHeight - 60;
  const by = (dy) => { sc.scrollTop += dy; return true; };
  if (e.ctrlKey && !e.altKey) {
    if (e.key === "d") return by(page / 2);
    if (e.key === "u") return by(-page / 2);
    return false;
  }
  if (e.altKey || e.metaKey) return false;
  const k = e.key;
  if (k !== "g") gPending = false;
  switch (k) {
    case "j": case "ArrowDown": return by(48);
    case "k": case "ArrowUp": return by(-48);
    case " ": return by(e.shiftKey ? -page : page);
    case "PageDown": return by(page);
    case "PageUp": return by(-page);
    case "Home": sc.scrollTop = 0; return true;
    case "End": case "G": sc.scrollTop = sc.scrollHeight; return true;
    case "g":
      if (gPending) { gPending = false; sc.scrollTop = 0; } else gPending = true;
      return true;
    default: return false;
  }
}

// 表示をクリックしたとき、Vim のカーソルをそこへ動かす。リンクならそのまま開く（Enter）。
function onClick({ pos, link }) {
  if (pos == null) return;
  if (viewOnly && !link) return; // 見るだけ: カーソルは動かさない（リンクだけ開く）
  const [l, c] = view.lineColAt(pos);
  const m = (last.mode || "n")[0];
  if (m === "n") gui.write(`:call cursor(${l},${c})\r` + (link ? "\r" : ""));
  else if (m === "i") gui.write(`\x0f:call cursor(${l},${c})\r`);
}

// 画面側のエラーを、下のバーに赤く出す（何が起きたか分かるように）。ログにも残る（main 側）。
function showError(msg) {
  const el = $("err");
  if (!el) return;
  el.textContent = "エラー: " + String(msg).slice(0, 160);
  el.hidden = false;
  clearTimeout(showError._t);
  showError._t = setTimeout(() => { el.hidden = true; }, 12000);
}

async function boot() {
  window.addEventListener("error", (e) => showError(e.message || e.error));
  window.addEventListener("unhandledrejection", (e) => showError(e.reason && e.reason.message || e.reason));
  view = createView({ parent: $("view"), getImageURL: imageURL, getImageSize: imageSize, onImageSize, onClick });

  term = new Terminal({
    fontFamily: '"JetBrains Mono", "Noto Sans Mono CJK JP", ui-monospace, monospace',
    fontSize: 14,
    cursorBlink: false,
    allowProposedApi: true,
    scrollback: 0,
    theme: { background: "#ffffff", foreground: "#1f2328", cursor: "#1f2328", cursorAccent: "#ffffff", selectionBackground: "#b6d6ff" },
  });
  fit = new FitAddon();
  term.loadAddon(fit);
  term.open($("term"));
  try { await document.fonts.ready; } catch { /* ignore */ }

  term.attachCustomKeyEventHandler((e) => {
    if (e.type !== "keydown") return !(viewOnly && !needsTerminal(last)); // 見るだけ中は keyup/keypress も Vim へ流さない
    if (e.key === "F2") { e.preventDefault(); setViewOnly(!viewOnly); return false; }
    if (viewOnly && !needsTerminal(last)) { viewOnlyKey(e); return false; }
    return true;
  });
  term.onData((d) => { if (viewOnly && !needsTerminal(last)) return; gui.write(d); });
  gui.onData((d) => term.write(d));
  gui.onState((s) => { try { applyState(s); } catch (e) { console.error("applyState failed: " + (e && e.stack || e)); showError(e && e.message || e); } });
  gui.onExit(() => { $("mode").textContent = "EXIT"; });

  const { cols, rows } = fitTerm();
  gui.start(cols, rows);
  term.focus();

  window.addEventListener("resize", () => {
    const d = fitTerm();
    gui.resize(d.cols, d.rows);
  });
  // どこを押しても、キー入力は端末（Vim）へ戻す
  document.addEventListener("mousedown", () => setTimeout(() => term.focus(), 0));
  window.addEventListener("focus", () => term.focus());

  // デバッグ・テスト用フック
  window.__gui = {
    term, view,
    state: () => last,
    send: (d) => gui.write(d),
    isExpanded: () => expanded,
    isViewOnly: () => viewOnly,
    setViewOnly,
    screen: () => {
      const b = term.buffer.active;
      const out = [];
      for (let i = 0; i < term.rows; i++) out.push(b.getLine(i)?.translateToString(true) ?? "");
      return out;
    },
  };
}

document.addEventListener("DOMContentLoaded", boot);
