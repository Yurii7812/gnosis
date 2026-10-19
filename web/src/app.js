// 画面側。Vim（本体）の状態を、マークダウンの見た目で映し、端末の画面は必要なときだけ見せる。
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { createView } from "./view.js";
import { showLauncher } from "./launcher.js";

const gui = window.gui;
const $ = (id) => document.getElementById(id);

const STRIP_ROWS = 2; // 普段は端末の下の 2 行（ステータス行・コマンド行/メッセージ）だけ見せる。本文の最後の行は表示側にあるので出さない
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
  if (!on) $("termwrap").style.clipPath = "";
  term.focus();
}

// 端末の全面表示のうち、ポップアップの長方形だけを見せる（背景は下のマークダウン表示のまま）
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

// 端末の画面そのものが要る場面（確認・fzf・ポップアップ・Enter 待ちなど）か
// ポップアップ（検索など）だけが理由のときは、背景の表示を変えず、ポップアップの場所にだけ端末を重ねる。
// 確認・Enter 待ち・シェルなど、端末の画面全体が要る場面は、これまでどおり全面に広げる。
function overlayOnly(s) {
  const m = (s.mode || "n")[0];
  return (s.popuppos || []).length > 0 && m !== "r" && m !== "!" && s.mode !== "rm";
}

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
}

function applyState(s) {
  applyLook(s);
  const prevCur = last.cur;
  last = { ...last, ...s, lines: undefined };
  if (viewInCmd) {
    if ((s.mode || "n")[0] === "c") viewSawCmd = true;
    else if (viewSawCmd) viewInCmd = false;
  }
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
  applyOverlay(last);

  // バッファの内容とカーソルをマークダウンで映す（端末バッファは映さない）
  if (s.bt === "terminal") return;
  const fileChanged = viewOnly && s.file && s.file !== lastViewFile;
  if (s.file) lastViewFile = s.file;
  if (s.lines) { view.setText(s.lines.join("\n")); preloadImages(s.lines); }
  if (fileChanged) view.view.scrollDOM.scrollTop = 0; // 見るだけのときは別のノートに移ったら先頭から
  if (s.vtext) view.setVtext(s.vtext);
  if (s.cur) view.setVim({ cur: s.cur, mode: s.mode || "n", vis: s.vis });
  // 見るだけで検索して、カーソルが動いたら、その行を出す
  if (viewOnly && s.cur && prevCur && !viewInCmd && viewFollow > Date.now() && m === "n" && (prevCur[0] !== s.cur[0] || prevCur[1] !== s.cur[1])) {
    viewFollow = 0;
    view.revealCursor();
  }
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

// ---------------------------------------------------------------- 見るだけモード
// Alt+V（View）で「見るだけ」と「普通の Vim」を切り替える。見るだけのときは、カーソルを出さず、
// キーを Vim に送らない（ノートは絶対に変わらない）。j/k・矢印・Space・PageUp/Down・gg/G・
// Ctrl-d/u でスクロールし、リンクはクリックで開く。確認・fzf などの端末が要る場面では、
// 普通どおりキーを Vim へ送る。
let viewOnly = false;
let lastViewFile = "";

function setViewOnly(on) {
  viewOnly = !!on;
  $("view").classList.toggle("view-only", viewOnly);
  view.setViewOnly(viewOnly);
  if (!viewOnly) view.revealCursor(false);
  if (!viewOnly) view.setVim({ cur: last.cur || [1, 1], mode: last.mode || "n", vis: last.vis }); // カーソルへ戻す
  applyState({ mode: last.mode, file: last.file, bt: last.bt, popups: last.popups });
}

// 見るだけで、キーを Vim へ流さない場面か（端末が要る場面・コマンドライン/質問の入力中は流す）
function viewBlocks() {
  return viewOnly && !viewInCmd && !needsTerminal(last) && (last.mode || "n")[0] !== "c";
}

// 見るだけでも Vim に届けるキー（編集しない SYN の操作）。完全に一致したらすぐ送る。
// どれも他の候補の前半にはならない（待たずに送れる）。ここに無いキーは、スクロール以外は捨てる。
const VIEW_PASS = new Set([
  "/", "?", "n", "N", "*", "#", "gs", "gm", " ", "\t", "\x1b[Z", "\r", "\x7f", "_",
  "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
  "\\h", "\\H", "\\0", "\\i", "\\d", "\\.", "\\L", "\\gi", "\\r", "\\bu", "\\k", "\\j", "\\J", "\\sc",
]);
const VIEW_SCROLL_SEQ = new Set(["gg"]);
let viewPend = "";
// 検索（/ ? n N * #）: コマンドラインに入ったのが画面に伝わる前に打たれたキーも Vim へ届けるため、
// 検索を始めたら、コマンドラインが終わるまで（または 1.5 秒で入らなければ）キーを流す。
// 終わって、カーソルが動いたら、その行を真ん中に出す。
let viewInCmd = false;
let viewSawCmd = false;
let viewFollow = 0;
function viewStartSearch(key) {
  viewFollow = Date.now() + 30000;
  if (key === "/" || key === "?") {
    viewInCmd = true;
    viewSawCmd = false;
    setTimeout(() => { if (!viewSawCmd) viewInCmd = false; }, 1500);
  }
}

function vimKeyString(e) {
  if (e.ctrlKey || e.altKey || e.metaKey) return null;
  switch (e.key) {
    case "Tab": return e.shiftKey ? "\x1b[Z" : "\t";
    case "Enter": return "\r";
    case "Backspace": return "\x7f";
    default: return e.key.length === 1 ? e.key : null;
  }
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
  const ks = vimKeyString(e);
  if (ks != null) {
    const cand = viewPend + ks;
    if (VIEW_PASS.has(cand)) {
      viewPend = "";
      if ("/?nN*#".includes(cand) && cand.length === 1) viewStartSearch(cand);
      gui.write(cand);
      return true;
    }
    if (VIEW_SCROLL_SEQ.has(cand)) { viewPend = ""; sc.scrollTop = 0; return true; }
    const isPrefix = [...VIEW_PASS, ...VIEW_SCROLL_SEQ].some((x) => x.startsWith(cand));
    if (isPrefix) { viewPend = cand; return true; }
    const hadPend = viewPend !== "";
    viewPend = "";
    if (hadPend) return true; // 候補から外れた続きは捨てる
  }
  switch (e.key) {
    case "j": case "ArrowDown": return by(48);
    case "k": case "ArrowUp": return by(-48);
    case "PageDown": return by(page);
    case "PageUp": return by(-page);
    case "Home": sc.scrollTop = 0; return true;
    case "End": case "G": sc.scrollTop = sc.scrollHeight; return true;
    default: return false;
  }
}

// 表示をクリックしたとき、Vim のカーソルをそこへ動かす。リンクならそのまま開く（Enter）。
function onClick({ pos, link, alt }) {
  if (pos == null) return;
  // Alt + クリック: リンクでも開かず、カーソルだけをそこへ動かす（zk → g などに使う）
  if (alt) link = false;
  if (viewOnly && !link) return; // 見るだけ: カーソルは動かさない（リンクだけ開く）
  const [l, c] = view.lineColAt(pos);
  const m = (last.mode || "n")[0];
  // 打った :call … が下の行に残らないよう、直後に redraw して空のメッセージで消す
  const mv = `:call cursor(${l},${c})|redraw|echo ""\r`;
  if (m === "n") gui.write(mv + (link ? "\r" : ""));
  else if (m === "i") gui.write("\x0f" + mv);
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
    theme: { background: "#fafafa", foreground: "#1f1f1f", cursor: "#1f1f1f", cursorAccent: "#fafafa", selectionBackground: "#b5cfee" },
  });
  fit = new FitAddon();
  term.loadAddon(fit);
  term.open($("term"));
  try { await document.fonts.ready; } catch { /* ignore */ }

  // 見るだけで自分で処理したキーは、同じキーの keypress / keyup も端末に渡さない
  // （/ を打つと viewInCmd が真になり、続く keypress が通って // になっていた）
  let swallowed = false;
  term.attachCustomKeyEventHandler((e) => {
    if (e.type !== "keydown") {
      const sw = swallowed;
      if (e.type === "keyup") swallowed = false;
      return sw ? false : !viewBlocks();
    }
    swallowed = false;
    if (e.altKey && !e.ctrlKey && !e.metaKey && e.code === "KeyV") { e.preventDefault(); swallowed = true; setViewOnly(!viewOnly); return false; }
    if (viewBlocks()) { swallowed = true; viewOnlyKey(e); return false; }
    return true;
  });
  term.onData((d) => { if (viewBlocks()) return; gui.write(d); });
  gui.onData((d) => term.write(d));
  gui.onState((s) => { try { applyState(s); } catch (e) { console.error("applyState failed: " + (e && e.stack || e)); showError(e && e.message || e); } });
  gui.onExit(() => { $("mode").textContent = "EXIT"; });

  // 起動画面で vault を選んで Enter を押したら（GNOSIS_ROOT 指定のときはすぐ）Vim を起動する
  await showLauncher((vaultPath, settings) => {
    applyLook({ palette: null, fontSize: settings && settings.fontSize });
    const { cols, rows } = fitTerm();
    gui.start(cols, rows, vaultPath);
    term.focus();
  });

  window.addEventListener("resize", () => {
    const d = fitTerm();
    gui.resize(d.cols, d.rows);
  });
  // どこを押しても、キー入力は端末（Vim）へ戻す
  document.addEventListener("mousedown", () => setTimeout(() => { if (document.getElementById("launcher").hidden) term.focus(); }, 0));
  window.addEventListener("focus", () => { if (document.getElementById("launcher").hidden) term.focus(); });

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
