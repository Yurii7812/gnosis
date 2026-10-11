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
  el.textContent = MODE_LABEL[m] || String(s.mode).toUpperCase();
  el.className = "mode " + (MODE_CLASS[m] || "normal");
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
  if (s.lines) view.setText(s.lines.join("\n"));
  if (s.vtext) view.setVtext(s.vtext);
  if (s.cur) view.setVim({ cur: s.cur, mode: s.mode || "n", vis: s.vis });
}

// ---------------------------------------------------------------- 起動

async function imageURL(src) {
  if (/^[a-z]+:\/\//i.test(src) || src.startsWith("data:")) return src;
  const bytes = await gui.readImage(last.file, src);
  if (!bytes) return null;
  return URL.createObjectURL(new Blob([bytes]));
}

// 表示をクリックしたとき、Vim のカーソルをそこへ動かす。リンクならそのまま開く（Enter）。
function onClick({ pos, link }) {
  if (pos == null) return;
  const [l, c] = view.lineColAt(pos);
  const m = (last.mode || "n")[0];
  if (m === "n") gui.write(`:call cursor(${l},${c})\r` + (link ? "\r" : ""));
  else if (m === "i") gui.write(`\x0f:call cursor(${l},${c})\r`);
}

async function boot() {
  view = createView({ parent: $("view"), getImageURL: imageURL, onClick });

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

  term.onData((d) => gui.write(d));
  gui.onData((d) => term.write(d));
  gui.onState(applyState);
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
    screen: () => {
      const b = term.buffer.active;
      const out = [];
      for (let i = 0; i < term.rows; i++) out.push(b.getLine(i)?.translateToString(true) ?? "");
      return out;
    },
  };
}

document.addEventListener("DOMContentLoaded", boot);
