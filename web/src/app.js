// 画面側。Vim（本体）の状態を、マークダウンの見た目で映し、端末の画面は必要なときだけ見せる。
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { createView } from "./view.js";
import { showLauncher } from "./launcher.js";
import { createGuiEdit } from "./guiedit.js";
import { createPanes, KIND_LABEL, VIEW_KINDS } from "./panes.js";
import { EXTRA_VIEWS } from "./extra-views.js";
import { rank, readings } from "./palette-core.js";
import { createNavSidebar, createIndexBrowser, navActions } from "./nav.js";
import { createCalendar } from "./calendar.js";
import { createMandala } from "./mandala.js";
import { createCanvas } from "./canvas.js";
import { form, toast, noteSub, imeActive, popupMenu } from "./ui.js";
import { createDocks } from "./docks.js";
import { notesPanel, featuresPanel, linksPanel, outlinePanel, searchPanel } from "./panels.js";
import { createSwitcher } from "./switcher.js";
import { icon } from "./icons.js";

const gui = window.gui;
const $ = (id) => document.getElementById(id);

const STRIP_ROWS = 2; // 普段は端末の下の 2 行（ステータス行・コマンド行/メッセージ）だけ見せる。本文の最後の行は表示側にあるので出さない
let term = null;
let fit = null;
let view = null;
let guiEdit = null; // GUI 編集モード（src/guiedit.js）
let panes = null;   // タブ・分割ペイン（src/panes.js）
let cell = { w: 8, h: 18 };
let last = { file: "", mode: "n", bt: "", popups: 0, mod: 0, cmdtype: "" };
let expanded = false;
let collapseTimer = null;
let nav = null;     // 索引ナビ（左のバーのパネル。src/nav.js）
let docks = null;   // 左端のアイコン列と左右のバー（src/docks.js）
let switcher = null; // クイックスイッチャー（Ctrl+O。src/switcher.js）
let curLines = [];  // Vim で開いているノートの行（アウトライン用）
let noteRoot = "";  // vault のノートのフォルダ（相対パスを絶対パスにする）

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
    // アクセントは Obsidian の紫ではなく黒（ダークでは明るい灰色）。その上の文字は背景の色
    r.setProperty("--accent", p.accent || p.link);
    r.setProperty("--on-accent", p.bg);
    r.setProperty("--heading", p.heading);
    r.setProperty("--subheading", p.subheading || p.heading);
    r.setProperty("--selection", p.selection);
    r.setProperty("--cursorline", p.cursorline);
    // 左右のバー・タブの列は Obsidian の background-secondary（ダーク #262626・ライト #F6F6F6）ほどの濃さ
    r.setProperty("--bg-2", `color-mix(in srgb, ${p.fg} ${dark ? 5 : 4}%, ${p.bg})`);
    r.setProperty("--bg-3", `color-mix(in srgb, ${p.fg} ${dark ? 10 : 9}%, ${p.bg})`);
    r.setProperty("--fg-dim", p.muted || `color-mix(in srgb, ${p.fg} 62%, ${p.bg})`);
    r.setProperty("--line", `color-mix(in srgb, ${p.fg} ${dark ? 9 : 12}%, ${p.bg})`);
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
}

function applyState(s) {
  applyLook(s);
  if (guiEdit && guiEdit.isOn()) {
    // GUI 編集中は、画面が編集の主体。Vim の状態（別のノートを開いた・保存時の同期で内容が変わった）だけ取り込む
    last = { ...last, file: s.file !== undefined ? s.file : last.file, bt: s.bt !== undefined ? s.bt : last.bt };
    guiEdit.onVimState(s);
    followNav(s);
    return;
  }
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
  if (last.copyStack) el.textContent += " · COPY STACK";
  if (last.linkSource) el.textContent += " · LINK SOURCE";
  el.className = "mode " + (showView ? "viewonly" : (MODE_CLASS[m] || "normal"));
  $("file").textContent = s.file ? s.file.split("/").pop() : "";
  $("dirty").textContent = s.mod ? "●" : "";
  followNav(s);

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
  view.setLinkSource(!!last.linkSource);
  if (s.lines) { view.setText(s.lines.join("\n")); preloadImages(s.lines); curLines = s.lines; outlineSoon(); }
  if (fileChanged) view.view.scrollDOM.scrollTop = 0; // 見るだけのときは別のノートに移ったら先頭から
  if (s.vtext) view.setVtext(s.vtext);
  if (s.cur) view.setVim({ cur: s.cur, mode: s.mode || "n", vis: s.vis });
  // 見るだけで検索して、カーソルが動いたら、その行を出す
  if (viewOnly && s.cur && prevCur && !viewInCmd && viewFollow > Date.now() && m === "n" && (prevCur[0] !== s.cur[0] || prevCur[1] !== s.cur[1])) {
    viewFollow = 0;
    view.revealCursor();
  }
}

// ペインの大きさが変わったら、Vim の端末の大きさを合わせ直す（Vim のタブが見えているときだけ）
let fitTimer = null;
function scheduleFit() {
  clearTimeout(fitTimer);
  fitTimer = setTimeout(() => {
    const st = $("stage");
    if (!term || !st || st.offsetWidth < 50 || st.offsetHeight < 50 || st.closest(".hidden-tab")) return;
    const d = fitTerm();
    gui.resize(d.cols, d.rows);
    view?.refresh?.();
  }, 60);
}

// ---------------------------------------------------------------- 索引ナビ・索引ブラウザ・カレンダー・曼荼羅・キャンバス
// 読むのは python/app_model.py（gui.query）、書くのは Vim（gui.op → gnosis#app_op、本文の保存は gui.commitNote → :write）。
const absOf = (rel) => (!rel || rel.startsWith("/") || /^[A-Za-z]:[\\/]/.test(rel) ? rel : (noteRoot ? noteRoot.replace(/[\\/]$/, "") + "/" + rel : rel));
const relOf = (file) => { const r = noteRoot.replace(/[\\/]$/, "") + "/"; return file && noteRoot && file.startsWith(r) ? file.slice(r.length) : file; };
let navFile = "", navMod = 0, navTimer = null;
// 戻る・進む（ツールバー・マウスの戻る/進むボタン・Alt+←/→）。履歴は Vim のもの（⌫ と \.）
async function historyGo(dir) {
  if (guiEdit && guiEdit.isOn() && !(await setMode("vim"))) return;
  const r = await gui.op(dir < 0 ? "go_back" : "go_forward", {});
  if (!r.ok) toast(r.error || "移れませんでした");
  else panes.showVim();
}
function showHistory(s) {
  if (!s.hist) return;
  const [b, f] = s.hist;
  for (const el of document.querySelectorAll("#history-tools [data-hist]")) el.disabled = el.dataset.hist === "back" ? !b : !f;
}
function followNav(s) {
  showHistory(s);
  if (!nav) return;
  if (s.file !== undefined && s.bt !== "terminal" && s.file && s.file !== navFile) {
    navFile = s.file;
    const f = s.file;
    setNoteTitle(f.split("/").pop().replace(/\.md$/i, ""));
    Promise.resolve(nav.follow(f)).then(() => { const i = nav.info(); if (navFile === f && i && i.title && !i.missing) setNoteTitle(i.title, i); });
    docks && docks.follow(f);
    rememberRecent(f);
  }
  if (s.mod !== undefined) {
    if (navMod && !s.mod) refreshAppViewsSoon();      // 保存した: 索引の情報が変わったかもしれない
    navMod = s.mod;
  }
}
function refreshAppViewsSoon(ms = 600) {
  clearTimeout(navTimer);
  navTimer = setTimeout(() => { nav && nav.refresh(); docks && docks.refresh(); }, ms);   // 保存のあとの同期（別のノートの Group: など）を待ってから
}

// ノートの見出しとタブに、開いているノートの題を出す（Obsidian と同じ）
function setNoteTitle(title, info) {
  const el = $("vh-title");
  if (el) {
    el.textContent = "";
    const crumbs = info && info.crumbs && info.crumbs[0] ? info.crumbs[0].filter((x) => x.via !== "topic").slice(0, -1) : [];
    if (crumbs.length) el.appendChild(document.createTextNode(crumbs.slice(-2).map((x) => x.label || x.title).join(" / ") + " / "));
    const b = document.createElement("b"); b.textContent = title; el.appendChild(b);
    el.title = info && info.rel ? info.rel : title;
  }
  panes && panes.setVimTitle(title);
}

async function vimOpen(rel) {
  const r = await gui.openNote(rel);
  if (!r.ok) { showError(r.error || "開けませんでした"); return false; }
  panes.showVim();
  return true;
}

const appCtx = {
  query: (m, p) => gui.query(m, p),
  op: async (op, p) => {
    if (guiEdit && guiEdit.isOn() && !(await setMode("vim"))) return { ok: false, error: "GUI 編集を終えられませんでした" };
    const r = await gui.op(op, p);
    refreshAppViewsSoon(300);
    if (r.ok && ["index_new", "topic_new", "diary_open", "note_new"].includes(op)) panes.showVim();
    return r;
  },
  open: (rel) => vimOpen(rel),
  showVim: () => panes.showVim(),
  focusVim: () => term && term.focus(),
  changed: () => refreshAppViewsSoon(300),
  newNote: (title) => newNote(title),
  menu: (x, y, items) => popupMenu(x, y, items),
  // ノートを開いて、その行へ（検索の結果）
  openAt: async (rel, line) => { if (await vimOpen(rel)) setTimeout(() => gotoLine(line), 200); },
  getLines: () => (guiEdit && guiEdit.isOn() ? view.view.state.doc.toString().split("\n") : curLines),
  gotoLine: (l) => gotoLine(l),
  readNote: (rel) => gui.readNote(absOf(rel)),
  // 本文を Vim に保存させる（保存時の同期が全部走る）。先に Vim の未保存を保存する。読んだときと違えば競合を返す
  commit: async (rel, text, hash) => {
    if (guiEdit && guiEdit.isOn() && guiEdit.state().file === absOf(rel)) return { ok: false, error: "GUI 編集で開いているノートです" };
    await gui.enterEdit();
    const r = await gui.commitNote(absOf(rel), text, hash, false);
    refreshAppViewsSoon();
    return r;
  },
  // タスクを完了に: 完了後の本文を作って Vim に保存させ、Vim は元のノートへ戻す
  completeTask: async (t) => {
    const back = last.file;
    const cur = await gui.readNote(absOf(t.file));
    if (!cur.ok) { toast(cur.error || "読めませんでした", "err"); return false; }
    const r = await gui.query("task.complete", { file: t.file, line: t.line });
    if (!r.ok || !r.result.changed) { toast((r.result && r.result.error) || r.error || "完了にできませんでした", "err"); return false; }
    await gui.enterEdit();
    const c = await gui.commitNote(absOf(t.file), r.result.text, cur.hash, false);
    if (back && back !== absOf(t.file)) await gui.openNote(back);
    if (!c.ok) { toast(c.conflict ? "ノートがほかで変わっていました。もう一度押してください" : (c.error || "保存できませんでした"), "err"); return false; }
    return true;
  },
};

const nativeViews = {
  dindex: () => createIndexBrowser(appCtx),
  calendar: (p) => createCalendar(appCtx, p),
  mandala: (p) => createMandala(appCtx, p),
  imandala: (p) => createMandala(appCtx, { index: p.rel, mode: p.mode }),
  canvas: (p) => createCanvas(appCtx, p),
};

function currentRel() { return relOf(last.file || ""); }
function titleOf(rel) { const i = nav && nav.info(); return i && i.rel === rel ? i.title : rel.split("/").pop().replace(/\.md$/, ""); }

async function pickNoteOfKind(kind, title) {
  const v = await form({
    title, ok: "開く",
    fields: [{ key: "file", label: "ノート", type: "picker", placeholder: "題で探す", load: async (q) => { const r = await gui.query("nav.notes", { q, kind }); return (r.ok ? r.result : []).map((x) => ({ value: x.rel, label: x.title, sub: noteSub(x) })); } }],
  });
  return v && v.file;
}

// 索引を曼荼羅で見る（索引か、トピック索引のあるノートのとき）
function openIndexMandala(rel) {
  const i = nav && nav.info();
  rel = rel || (i && !i.missing ? (i.entries ? i.rel : (i.topics && i.topics[0] ? i.topics[0].rel : "")) : "");
  if (!rel) { toast("索引（グループ）か、トピック索引のあるノートを開いているときに使えます", "err"); return; }
  panes.openOrFocus("imandala", { rel }, "曼荼羅: " + (rel === (i && i.rel) ? i.title : titleOf(rel)));
}

async function openMandala(mode) {
  const i = nav && nav.info();
  if (!mode && i && !i.missing && i.kind !== "mandala" && (i.entries || i.is_index)) { openIndexMandala(i.rel); return; }
  if (mode !== "pick" && mode !== "new" && i && i.kind === "mandala") { panes.openOrFocus("mandala", { rel: i.rel }, "曼荼羅: " + i.title); return; }
  if (mode === "pick") { const f = await pickNoteOfKind("mandala", "曼荼羅を開く"); if (f) panes.openOrFocus("mandala", { rel: f }, "曼荼羅: " + titleOf(f)); return; }
  const v = await form({
    title: "新しい曼荼羅", ok: "作る", note: "主題を真ん中に、副題を 8 つまで（あとから足せます）。今日の日記の「今日のノート」に載ります。",
    fields: [{ key: "title", label: "主題", required: true }, ...Array.from({ length: 8 }, (_, k) => ({ key: "s" + k, label: `副題 ${k + 1}` }))],
  });
  if (!v) return;
  const r = await appCtx.op("note_new", { kind: "mandala", title: v.title.trim(), subs: Array.from({ length: 8 }, (_, k) => v["s" + k].trim()) });
  if (!r.ok) { toast(r.error || "作れませんでした", "err"); return; }
  panes.openOrFocus("mandala", { rel: r.rel }, "曼荼羅: " + v.title.trim());
}

async function openCanvas(mode) {
  const i = nav && nav.info();
  if (mode !== "pick" && mode !== "new" && i && i.kind === "canvas") { panes.openOrFocus("canvas", { rel: i.rel }, "キャンバス: " + i.title); return; }
  if (mode === "pick") { const f = await pickNoteOfKind("canvas", "キャンバスを開く"); if (f) panes.openOrFocus("canvas", { rel: f }, "キャンバス: " + titleOf(f)); return; }
  const v = await form({ title: "新しいキャンバス", ok: "作る", note: "ノートや文字のカードを並べて矢印でつなぐ図です。今日の日記の「今日のノート」に載ります。", fields: [{ key: "title", label: "題", required: true }] });
  if (!v) return;
  const r = await appCtx.op("note_new", { kind: "canvas", title: v.title.trim() });
  if (!r.ok) { toast(r.error || "作れませんでした", "err"); return; }
  panes.openOrFocus("canvas", { rel: r.rel }, "キャンバス: " + v.title.trim());
}

function openIndexBrowser() { panes.openOrFocus("dindex", {}, "索引ブラウザ"); }
function openCalendar() { panes.openOrFocus("calendar", {}, "カレンダー"); }

// ---- 新しいノート（Ctrl+N・リボン・ノートのパネル・クイックスイッチャー）----
async function newNote(title) {
  if (!title) {
    const v = await form({ title: "新しいノート", ok: "作って書く", note: "今日の日記の「今日のノート」に載ります。索引に載せるのは、左のバーの「索引」から。", fields: [{ key: "title", label: "題", required: true }] });
    if (!v) return false;
    title = v.title.trim();
  }
  const r = await appCtx.op("note_new", { kind: "note", title });
  if (!r.ok) { toast(r.error || "作れませんでした", "err"); return false; }
  return true;
}

// アウトラインの見出しを押した: その行へ（Vim ならカーソルを動かす。GUI 編集なら編集欄で）
function gotoLine(l) {
  if (guiEdit && guiEdit.isOn()) {
    const v = view.view, doc = v.state.doc;
    const ln = doc.line(Math.max(1, Math.min(l, doc.lines)));
    v.dispatch({ selection: { anchor: ln.from }, scrollIntoView: true });
    v.focus();
    return;
  }
  panes.showVim();
  const m = (last.mode || "n")[0];
  const mv = `:call cursor(${l},1)|normal! zt|redraw|echo ""\r`;
  if (viewOnly) { const doc = view.view.state.doc; view.view.scrollDOM.scrollTop = view.view.lineBlockAt(doc.line(Math.max(1, Math.min(l, doc.lines))).from).top; return; }
  if (m === "n") gui.write(mv);
  else if (m === "i") gui.write("\x0f" + mv);
  term.focus();
}

// ---- 左端のアイコン列と左右のバー（Obsidian と同じ並び）。開け閉め・幅はこの PC の好み（localStorage） ----
function viewsMenu(x, y) {
  popupMenu(x, y, [
    ...VIEW_KINDS.map((k) => ({ label: KIND_LABEL[k], run: () => panes.openView(k) })), "-",
    ...EXTRA_VIEWS.map(([k, t]) => ({ label: t, run: () => panes.openExtra(k) })), "-",
    { label: "ビューを最新の状態に更新", run: () => panes.reloadViews() },
  ]);
}
function setSidebar(on) {   // 互換: 左のバーの「索引」を出す・隠す
  if (on) docks.show("index"); else docks.toggle("left", false);
}
function initDocks() {
  const ribbon = [
    { id: "switcher", icon: "file-search", title: "ノートを開く（Ctrl+O）", run: () => switcher.open() },
    { id: "search", icon: "search", title: "検索（Ctrl+Shift+F）", run: () => openSearch() },
    { id: "new", icon: "note-plus", title: "新しいノート（Ctrl+N）", run: () => newNote() },
    { id: "today", icon: "today", title: "今日の日記を開く", run: () => appCtx.op("diary_open", {}) },
    { id: "calendar", icon: "calendar", title: "カレンダー（Alt+C）", run: () => openCalendar() },
    { id: "browser", icon: "columns", title: "索引ブラウザ（Index → ノート → トピック索引 を列で辿る）", run: () => openIndexBrowser() },
    { id: "graph", icon: "graph", title: "グラフ", run: () => panes.openView("graph") },
    { id: "mandala", icon: "mandala", title: "曼荼羅（今のノートが曼荼羅なら開く・索引なら曼荼羅で見る・ほかは新しく作る）", run: () => openMandala() },
    { id: "canvas", icon: "canvas", title: "キャンバス（今のノートがキャンバスなら開く・無ければ新しく作る）", run: () => openCanvas() },
    { id: "palette", icon: "command", title: "コマンドパレット（Ctrl+P）", run: () => openPalette() },
    { id: "views", icon: "cards", title: "表示専用のビュー（カード・テーブル・時系列・検索…）", bottom: true, run: (e) => { const r = document.querySelector('[data-ribbon="views"]').getBoundingClientRect(); viewsMenu(r.right + 4, r.top); } },
    { id: "features", icon: "features", title: "全機能（左のバーの「機能」）", bottom: true, run: () => { const p = docks.show("features"); p && p.focusSearch && p.focusSearch(); } },
  ];
  const panels = [
    { id: "index", side: "left", icon: "index", title: "索引（ダブルインデックス: Index からの道・載っている索引・トピック索引。Alt+I で索引語を探す）",
      create: (el) => { el.id = "sidebar"; nav = createNavSidebar(el, appCtx); el.addEventListener("gnosis-open-editor", (e) => { if (e.detail === "mandala") openMandala(); else if (e.detail === "imandala") openIndexMandala(); else openCanvas(); }); return { refresh: () => {} }; } },
    { id: "notes", side: "left", icon: "files", title: "ノート（全部のノート・並び替え）", create: notesPanel(appCtx) },
    { id: "search", side: "left", icon: "search", title: "検索（Obsidian と同じ書き方の全文検索。Ctrl+Shift+F）", create: searchPanel(appCtx) },
    { id: "features", side: "left", icon: "features", title: "機能（全部の機能。押すと実行）", create: featuresPanel(async () => { if (!vimCmds) { try { vimCmds = await gui.vimCommands(); } catch { vimCmds = []; } } return paletteItems(); }) },
    { id: "links", side: "right", icon: "link", title: "リンク（関係・バックリンク・出ていくリンク）", create: linksPanel(appCtx) },
    { id: "outline", side: "right", icon: "outline", title: "アウトライン（見出し）", create: outlinePanel(appCtx) },
  ];
  docks = createDocks({ ribbonEl: $("ribbon"), leftEl: $("leftdock"), rightEl: $("rightdock"), leftSplit: $("leftdock-split"), rightSplit: $("rightdock-split"), centerEl: $("center"), panels, ribbon, onResize: () => scheduleFit(), menu: popupMenu });
  docks.panel("index");     // 索引ナビは、隠れていても今のノートの情報（nav.info）に使う
  switcher = createSwitcher({ query: (m, p) => gui.query(m, p), open: (rel) => vimOpen(rel), create: (t) => newNote(t), onClose: () => backToInputSoon(), recent: () => recentNotes() });
}
// 検索のパネルを出して、欄へ（q があればそれで探す）
function openSearch(q) { const p = docks.show("search"); if (p && p.focusSearch) p.focusSearch(q); }
// 最近開いたノート（クイックスイッチャーの最初の一覧。この PC だけ）
function recentNotes() { try { return JSON.parse(localStorage.getItem("gnosis.recent") || "[]"); } catch { return []; } }
function rememberRecent(file) {
  const rel = relOf(file);
  if (!rel || rel.startsWith("/")) return;
  const list = [rel, ...recentNotes().filter((x) => x !== rel)].slice(0, 40);
  try { localStorage.setItem("gnosis.recent", JSON.stringify(list)); } catch { /* ignore */ }
}
let outlineTimer = null;
function outlineSoon() {
  if (!docks || !docks.isVisible("outline")) return;
  clearTimeout(outlineTimer);
  outlineTimer = setTimeout(() => { const p = docks.panel("outline"); p.update && p.update(); }, 250);
}
function backToInputSoon() { setTimeout(() => { if (guiEdit && guiEdit.isOn()) view.focus(); else term && term.focus(); }, 0); }

// ---------------------------------------------------------------- コマンドパレット（全部の機能の入口。ボタン・キーと同じ操作を呼ぶ）
let vimCmds = null;
function paletteItems() {
  const items = [];
  const add = (group, label, keywords, run) => items.push({ group, label, keywords: (keywords || "") + " " + readings(label + " " + group), run });
  add("モード", "Real Vim で編集", "vim mode 本物", () => setMode("vim"));
  add("モード", "GUI 編集モード（Vim を使わない）", "gui edit editor 編集", () => setMode("gui"));
  add("モード", "閲覧専用モード", "view readonly 閲覧", () => setMode("view"));
  for (const k of VIEW_KINDS) add("ビュー", `${KIND_LABEL[k]}を開く`, `${k} view`, () => panes.openView(k));
  for (const [k, t] of EXTRA_VIEWS) add("ビュー", `${t}を開く`, `${k} view 追加ビュー`, () => panes.openExtra(k));
  add("ビュー", "機能一覧をタブで開く", "features list 一覧 全機能", () => panes.openFeatures());
  add("バー", "左のバーを出す・隠す", "left sidebar toggle 左 サイドバー", () => docks.toggle("left"));
  add("バー", "右のバーを出す・隠す", "right sidebar toggle 右 サイドバー", () => docks.toggle("right"));
  add("バー", "索引（左のバー）を出す", "index nav sidebar 索引 サイドバー double index", () => docks.show("index"));
  add("バー", "ノートの一覧（左のバー）を出す", "files notes list ノート 一覧 最近", () => docks.show("notes"));
  add("バー", "機能（左のバー）を出す", "features 機能", () => { const p = docks.show("features"); p && p.focusSearch && p.focusSearch(); });
  add("バー", "リンク・バックリンク（右のバー）を出す", "backlinks links outgoing バックリンク リンク 関係", () => docks.show("links"));
  add("バー", "アウトライン（右のバー）を出す", "outline headings アウトライン 見出し", () => docks.show("outline"));
  add("ノート", "ノートを開く（クイックスイッチャー）", "quick switcher open note ctrl+o 開く 探す", () => switcher.open());
  add("ノート", "新しいノート", "new note ctrl+n 新規 作る", () => newNote());
  add("検索", "全文検索（Obsidian と同じ書き方）", "search full text ctrl+shift+f 検索 全文 探す", () => openSearch());
  add("索引", "索引語で探す", "search keyword 索引語 検索", () => { docks.show("index"); nav.focusSearch(); });
  add("索引", "索引ブラウザを開く（Index → ノート → トピック索引 を列で辿る）", "index browser miller 索引 ブラウザ", () => openIndexBrowser());
  add("索引", "今のノートを索引に載せる", "add index 載せる 索引語 \\l g", () => nav.info() && nav.actions.addToIndex(nav.info()));
  add("索引", "今のノートのトピック索引を作る", "topic index branchgroup zk トピック索引", () => nav.info() && nav.actions.newTopic(nav.info()));
  add("索引", "今の索引に新しいノートを作って載せる", "new note index zn 索引", () => { const i = nav.info(); if (i && i.entries) nav.actions.newInIndex(i); else toast("索引（グループ）を開いているときに使えます", "err"); });
  add("時間", "カレンダーを開く", "calendar カレンダー 日記 予定", () => openCalendar());
  add("時間", "今日の日記を開く", "diary today 日記", () => appCtx.op("diary_open", {}));
  add("曼荼羅", "曼荼羅を開く（今のノート）・新しい曼荼羅", "mandala 曼荼羅 マンダラート", () => openMandala());
  add("曼荼羅", "新しい曼荼羅を作る", "mandala new 曼荼羅", () => openMandala("new"));
  add("曼荼羅", "今の索引を曼荼羅で見る", "mandala index 曼荼羅 索引 インデックス", () => openIndexMandala());
  add("曼荼羅", "曼荼羅を選んで開く", "mandala open 曼荼羅", () => openMandala("pick"));
  add("キャンバス", "キャンバスを開く（今のノート）・新しいキャンバス", "canvas whiteboard キャンバス ホワイトボード", () => openCanvas());
  add("キャンバス", "新しいキャンバスを作る", "canvas new キャンバス", () => openCanvas("new"));
  add("キャンバス", "キャンバスを選んで開く", "canvas open キャンバス", () => openCanvas("pick"));
  add("ビュー", "ビューを最新の状態に更新", "refresh reload 更新", () => panes.reloadViews());
  add("移動", "戻る（前に開いていたノート）", "back history 戻る", () => historyGo(-1));
  add("移動", "進む", "forward history 進む", () => historyGo(1));
  add("タブ", "Vim のタブへ移る", "vim tab", () => panes.showVim());
  add("タブ", "次のタブ", "next tab", () => panes.cycle(1));
  add("タブ", "前のタブ", "previous tab", () => panes.cycle(-1));
  add("タブ", "閉じたタブを開く", "reopen closed tab 再開", () => panes.reopenClosed());
  add("タブ", "今のタブを閉じる", "close tab ctrl+w 閉じる", () => panes.closeActive());
  add("分割", "右に分割", "split right row 左右", () => panes.splitFocused("row"));
  add("分割", "下に分割", "split down col 上下", () => panes.splitFocused("col"));
  add("分割", "分割を解除", "unsplit join", () => panes.unsplitFocused());
  if (guiEdit.isOn()) {
    for (const [id, label, kw] of [["bold", "太字", "bold"], ["italic", "斜体", "italic"], ["strike", "取り消し線", "strike"], ["code", "コード", "code"], ["h1", "見出し 1", "heading"], ["h2", "見出し 2", "heading"], ["h3", "見出し 3", "heading"],
      ["bullet", "箇条書き", "list"], ["number", "番号つきリスト", "list"], ["task", "チェックボックスの行", "task"], ["checkbox", "チェックの切り替え", "check"], ["quote", "引用", "quote"], ["link", "リンクを入れる", "link"], ["openLink", "カーソルのリンクを開く", "open link"], ["undo", "元に戻す", "undo"], ["redo", "やり直す", "redo"], ["save", "保存", "save"]]) add("編集", label, kw, () => guiEdit.run(id));
  }
  for (const c of vimCmds || []) {
    items.push({ group: "Vim", label: ":" + c.name, keywords: "vim コマンド", run: async () => { await setMode("vim"); panes.showVim(); await sendVimCommand(c.name, c.nargs === "0"); } });
  }
  return items;
}

// Vim にコマンドを打つ。ESC と ":" を続けて送ると、Vim は Meta キー（Alt+:）と読むことがある（ttimeoutlen が短いため）。
// 文字がノーマルモードのコマンドとして流れ込まないよう、ESC のあと少し置いてから送る。
async function sendVimCommand(name, run) {
  gui.write("\x1b");
  await new Promise((r) => setTimeout(r, 80));
  gui.write(":" + name + (run ? "\r" : " "));
}

let palSel = 0, palItems = [];
async function openPalette() {
  const box = $("palette"), input = $("palette-input");
  if (!vimCmds) { try { vimCmds = await gui.vimCommands(); } catch { vimCmds = []; } }
  box.hidden = false; input.value = ""; palSel = 0;
  drawPalette();
  input.focus();
}
function closePalette() { $("palette").hidden = true; backToInputSoon(); }
function drawPalette() {
  const all = paletteItems();
  palItems = rank(all, $("palette-input").value);
  palSel = Math.min(palSel, Math.max(0, palItems.length - 1));
  const ul = $("palette-list"); ul.textContent = "";
  palItems.forEach((it, i) => {
    const li = document.createElement("li"); li.className = i === palSel ? "sel" : ""; li.setAttribute("role", "option");
    const l = document.createElement("span"); l.textContent = it.label;
    const g = document.createElement("span"); g.className = "grp"; g.textContent = it.group;
    li.append(l, g);
    li.addEventListener("mousedown", (e) => { e.preventDefault(); runPalette(i); });
    ul.appendChild(li);
  });
  const sel = ul.querySelector(".sel"); if (sel) sel.scrollIntoView({ block: "nearest" });
}
async function runPalette(i) {
  const it = palItems[i];
  if (!it) return;
  $("palette").hidden = true;
  try { await it.run(); } catch (e) { showError(e && e.message || e); }
}
function initPalette() {
  const input = $("palette-input");
  input.addEventListener("input", () => { palSel = 0; drawPalette(); });
  let composing = false;
  input.addEventListener("compositionstart", () => { composing = true; });
  input.addEventListener("compositionend", () => { composing = false; });
  input.addEventListener("keydown", (e) => {
    if (imeActive(e)) return;      // 変換中の Enter（確定）・矢印（候補）・Esc は、変換のために使う
    if (e.key === "ArrowDown") { e.preventDefault(); palSel = Math.min(palSel + 1, palItems.length - 1); drawPalette(); }
    else if (e.key === "ArrowUp") { e.preventDefault(); palSel = Math.max(palSel - 1, 0); drawPalette(); }
    else if (e.key === "Enter") { e.preventDefault(); runPalette(palSel); }
    else if (e.key === "Escape") { e.preventDefault(); closePalette(); }
  });
  input.addEventListener("blur", () => { setTimeout(() => { if (!composing && !$("palette").hidden && document.activeElement !== input) $("palette").hidden = true; }, 150); });
  initHotkeys();
}

// ---------------------------------------------------------------- モード（Real Vim / GUI 編集 / 閲覧専用）と、ツールバー
// 排他。GUI 編集から出るときは、保存して Vim に読み直させる。保存できない（競合の確認待ちなど）ときは移らない。
function currentMode() { return guiEdit && guiEdit.isOn() ? "gui" : viewOnly ? "view" : "vim"; }

async function setMode(m) {
  if (m === currentMode()) return true;
  if (guiEdit.isOn() && !(await guiEdit.leave())) return false;
  if (m === "view") setViewOnly(true);
  else if (m === "vim") { if (viewOnly) setViewOnly(false); term.focus(); }
  else if (m === "gui") { if (viewOnly) setViewOnly(false); if (!(await guiEdit.enter())) { refreshModeUI(); return false; } }
  refreshModeUI();
  return true;
}

function refreshModeUI() {
  const m = currentMode();
  for (const b of document.querySelectorAll("#modes [data-mode]")) b.setAttribute("aria-pressed", String(b.dataset.mode === m));
  const tools = $("edit-tools");
  if (tools) tools.hidden = m !== "gui";
  if (m === "gui") { const el = $("mode"); el.textContent = "EDIT"; el.className = "mode edit"; $("file").textContent = (guiEdit.state().file || "").split("/").pop(); }
}

// Obsidian と同じキー。Vim の画面では、ノーマルモードのときだけ取る（挿入・コマンドラインの Ctrl+P/N/O は Vim のまま）
//   Ctrl+P コマンドパレット・Ctrl+O ノートを開く・Ctrl+N 新しいノート・Ctrl+W タブを閉じる（Vim のタブは閉じない）
//   Ctrl+Tab / Ctrl+Shift+Tab 次・前のタブ・Ctrl+Shift+F 検索・Ctrl+Shift+P もパレット
function initHotkeys() {
  const inTerm = (t) => !!(t && t.closest && t.closest("#term"));
  const vimFree = () => { const m = (last.mode || "n")[0]; return viewOnly || (m === "n" && !needsTerminal(last)); };
  document.addEventListener("keydown", (e) => {
    if (!e.ctrlKey || e.altKey || e.metaKey || imeActive(e)) return;
    if (!document.getElementById("launcher").hidden) return;
    const t = e.target;
    const take = (fn) => { e.preventDefault(); e.stopPropagation(); fn(); };
    if (e.code === "Tab") return take(() => panes.cycle(e.shiftKey ? -1 : 1));
    if (e.shiftKey) {
      if (e.code === "KeyP") return take(() => openPalette());
      if (e.code === "KeyF") return take(() => openSearch());
      return;
    }
    // 打っている欄（クイックスイッチャー・パレットの中など）の中では、その欄の Ctrl+P/N（候補の上下）に任せる
    if (t && t.closest && t.closest(".qs, #palette")) return;
    if (inTerm(t) && !vimFree()) return;
    if (e.code === "KeyP") return take(() => openPalette());
    if (e.code === "KeyO") return take(() => switcher.open());
    if (e.code === "KeyN" && !(t && t.closest && t.closest("input, textarea"))) return take(() => newNote());
    if (e.code === "KeyW" && panes.activeKind() !== "vim") return take(() => panes.closeActive());
  }, true);
}

// ノートの見出しの「…」: このノートでできること
function noteMenu(x, y) {
  const i = nav && nav.info();
  const items = [];
  if (i && i.kind === "mandala") items.push({ label: "曼荼羅の画面で開く", run: () => openMandala() });
  if (i && i.kind === "canvas") items.push({ label: "キャンバスの画面で開く", run: () => openCanvas() });
  if (i && !i.missing && (i.entries || (i.topics && i.topics.length))) items.push({ label: "索引を曼荼羅で見る", run: () => openIndexMandala() });
  items.push(
    { label: "索引に載せる…", disabled: !i || i.missing || i.is_index, run: () => nav.actions.addToIndex(i) },
    { label: "トピック索引を作る…", disabled: !i || i.missing || !!i.entries, run: () => nav.actions.newTopic(i) },
    { label: "この索引に新しいノート…", disabled: !i || !i.entries, run: () => nav.actions.newInIndex(i) },
    "-",
    { label: "リンク・バックリンクを右のバーに", run: () => docks.show("links") },
    { label: "アウトラインを右のバーに", run: () => docks.show("outline") },
    "-",
    { label: "右に分割", run: () => panes.splitFocused("row") },
    { label: "下に分割", run: () => panes.splitFocused("col") },
    { label: "分割を解除", run: () => panes.unsplitFocused() },
    { label: "閉じたタブを開く", run: () => panes.reopenClosed() },
  );
  popupMenu(x, y, items);
}

function initToolbar() {
  for (const b of document.querySelectorAll("#modes [data-mode]")) b.addEventListener("click", () => setMode(b.dataset.mode));
  for (const b of document.querySelectorAll("#edit-tools [data-cmd]")) {
    // ボタンを押しても編集欄のフォーカス（選択）を失わない
    b.addEventListener("mousedown", (e) => e.preventDefault());
    b.addEventListener("click", () => { guiEdit.run(b.dataset.cmd); });
  }
  for (const b of document.querySelectorAll("#history-tools [data-hist]")) {
    b.appendChild(icon(b.dataset.hist === "back" ? "back" : "forward"));
    b.addEventListener("click", () => historyGo(b.dataset.hist === "back" ? -1 : 1));
  }
  const more = $("vh-more");
  more.appendChild(icon("more"));
  more.addEventListener("click", () => { const r = more.getBoundingClientRect(); noteMenu(r.left - 200, r.bottom + 2); });
  // マウスの戻る(3)・進む(4)ボタン
  window.addEventListener("mouseup", (e) => { if (e.button === 3 || e.button === 4) { e.preventDefault(); historyGo(e.button === 3 ? -1 : 1); } });
  initPalette();
  refreshModeUI();
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
function onClick({ pos, link, href, alt, mod }) {
  if (pos == null) return;
  // GUI 編集中: カーソルの移動はブラウザに任せる。描かれたリンクのクリック・Ctrl+クリックでそのノートを開く
  if (guiEdit && guiEdit.isOn()) {
    if (link && href) guiEdit.openAt(pos, href);
    else if (mod) guiEdit.openAt(pos, "");
    return;
  }
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
  view = createView({
    parent: $("view"), getImageURL: imageURL, getImageSize: imageSize, onImageSize, onClick,
    onCommand: (id) => (guiEdit ? guiEdit.run(id) : false),
    onUserChange: (u) => { if (guiEdit) guiEdit.onUserChange(u); outlineSoon(); },
  });
  guiEdit = createGuiEdit({ view, gui, $, getLast: () => last, showError, onChange: () => refreshModeUI() });
  panes = createPanes({
    root: $("workspace"), stageEl: $("stage"), gui,
    onNote: async (rel) => { const r = await gui.openNote(rel); if (!r.ok) showError(r.error || "開けませんでした"); else panes.showVim(); },
    onResize: () => scheduleFit(),
    // 機能一覧タブの中身(コマンドパレットと同じ項目)。Vim のコマンドの一覧は初回だけ Vim に聞く
    featureItems: async () => { if (!vimCmds) { try { vimCmds = await gui.vimCommands(); } catch { vimCmds = []; } } return paletteItems(); },
    nativeViews,
    plusItems: () => [
      { label: "索引ブラウザ", run: () => openIndexBrowser() }, { label: "カレンダー", run: () => openCalendar() },
      { label: "曼荼羅…", run: () => openMandala() }, { label: "キャンバス…", run: () => openCanvas() },
    ],
  });
  initDocks();
  initToolbar();

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
    if (e.altKey && !e.ctrlKey && !e.metaKey && e.code === "KeyV") { e.preventDefault(); swallowed = true; setMode(viewOnly ? "vim" : "view"); return false; }
    if (e.altKey && !e.ctrlKey && !e.metaKey && e.code === "KeyE") { e.preventDefault(); swallowed = true; setMode("gui"); return false; }
    if (e.altKey && !e.ctrlKey && !e.metaKey && (e.code === "KeyI" || e.code === "KeyC" || e.code === "ArrowLeft" || e.code === "ArrowRight")) { swallowed = true; return false; }   // 索引ナビ・カレンダー（document 側で開く）
    if (e.altKey && !e.ctrlKey && !e.metaKey && (e.code === "BracketRight" || e.code === "BracketLeft")) { e.preventDefault(); swallowed = true; panes.cycle(e.code === "BracketRight" ? 1 : -1); return false; }
    if (e.ctrlKey && e.shiftKey && e.code === "KeyP") { e.preventDefault(); swallowed = true; return false; }   // パレットは document 側で開く
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
    gui.noteRoot().then((r) => { noteRoot = r || ""; if (last.file) { navFile = ""; followNav(last); } });
    panes.restore().then(() => scheduleFit());
  });

  window.addEventListener("resize", () => { scheduleFit(); });
  // どこを押しても、キー入力は端末（Vim）へ戻す。GUI 編集中は編集欄に戻す
  const backToInput = () => { if (document.getElementById("launcher").hidden) { if (guiEdit.isOn()) { if (!document.activeElement || document.activeElement === document.body) view.focus(); } else term.focus(); } };
  // 索引ナビ・カレンダー・曼荼羅・キャンバス・ダイアログの中を押したときは、キー入力をそこに残す（Vim へ戻さない）
  const keepsFocus = (t) => t && t.closest && t.closest("#leftdock, #rightdock, .keepfocus, .gdlg-back, .featbox, .ctxmenu, #palette, .qs-back, input, textarea, select");
  document.addEventListener("mousedown", (e) => { if (keepsFocus(e.target)) return; setTimeout(backToInput, 0); });
  window.addEventListener("focus", () => { if (!keepsFocus(document.activeElement)) backToInput(); });
  // Alt+I: 索引ナビへ（索引語で探す）。Alt+C: カレンダー
  document.addEventListener("keydown", (e) => {
    if (!e.altKey || e.ctrlKey || e.metaKey) return;
    if (e.code === "ArrowLeft" || e.code === "ArrowRight") {
      // 文字を打っている欄の中では、ふつうの Alt+矢印のまま
      if (e.target && e.target.closest && e.target.closest("input, textarea, [contenteditable]") && !e.target.closest("#term")) return;
      e.preventDefault(); e.stopPropagation(); historyGo(e.code === "ArrowLeft" ? -1 : 1); return;
    }
    if (e.code === "KeyI") { e.preventDefault(); docks.show("index"); nav.focusSearch(); }
    else if (e.code === "KeyC") { e.preventDefault(); openCalendar(); }
  }, true);
  // GUI 編集中（編集欄にフォーカスがあるとき）のモード切替キー
  document.addEventListener("keydown", (e) => {
    if (!guiEdit.isOn() || !e.altKey || e.ctrlKey || e.metaKey) return;
    if (e.code === "KeyV") { e.preventDefault(); setMode("view"); }
    else if (e.code === "KeyE") { e.preventDefault(); setMode("vim"); }
  });

  // デバッグ・テスト用フック
  window.__gui = {
    term, view,
    state: () => last,
    send: (d) => gui.write(d),
    isExpanded: () => expanded,
    isViewOnly: () => viewOnly,
    setViewOnly,
    setMode, currentMode, guiEdit: () => guiEdit, panes: () => panes, openPalette,
    openSearch, nav: () => nav, appCtx, openMandala, openIndexMandala, openCanvas, openCalendar, openIndexBrowser, setSidebar, docks: () => docks, switcher: () => switcher, newNote,
    screen: () => {
      const b = term.buffer.active;
      const out = [];
      for (let i = 0; i < term.rows; i++) out.push(b.getLine(i)?.translateToString(true) ?? "");
      return out;
    },
  };
}

document.addEventListener("DOMContentLoaded", boot);
