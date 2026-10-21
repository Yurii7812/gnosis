// 読み取り専用のマークダウン表示（Obsidian 風ライブプレビューの描画だけ）。
// 編集は一切しない。本物の Vim のバッファの内容とカーソルを受け取って映す。
import { EditorState, StateEffect, StateField, Compartment, Facet, Annotation, Prec } from "@codemirror/state";
import { EditorView, Decoration, WidgetType, ViewPlugin, keymap } from "@codemirror/view";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { syntaxHighlighting, HighlightStyle } from "@codemirror/language";
import { tags } from "@lezer/highlight";

// 画像。画面から外れるとウィジェットは壊されて、戻ると作り直される。そのたびに空白・高さ 0 から
// 読み直すと「消えて、位置が跳ぶ」ので、読み込んだ URL と大きさを覚えて、すぐ表示・場所を先に確保する。
class ImageWidget extends WidgetType {
  constructor(alt, src, cfg, width) {
    super();
    this.alt = alt;
    this.src = src;
    this.cfg = cfg;
    this.width = width || ""; // <img width="50%"> の指定（空なら指定なし）
    // 大きさが分かっているか。分かった前後で別のウィジェットとみなして、高さを取り直させる。
    this.sized = !!(cfg.getImageSize && cfg.getImageSize(src));
  }
  eq(o) { return o.src === this.src && o.alt === this.alt && o.width === this.width && o.sized === this.sized; }
  // スクロールの長さの見積もり（本文の幅 約 800px に縮めたときの高さ）。分からないうちは 320。
  get estimatedHeight() {
    const sz = this.cfg.getImageSize?.(this.src);
    return sz ? Math.round(sz.h * Math.min(1, 800 / sz.w)) + 16 : 320;
  }
  toDOM() {
    const cfg = this.cfg;
    const wrap = document.createElement("span");
    wrap.className = "cm-md-img";
    const img = document.createElement("img");
    img.alt = this.alt;
    img.decoding = "async";
    const sz = cfg.getImageSize?.(this.src);
    if (sz) { img.width = sz.w; img.height = sz.h; } // 読み込む前から、場所を確保する
    else wrap.style.minHeight = "160px";
    if (this.width) { img.style.width = this.width; img.style.height = "auto"; }
    img.addEventListener("load", () => {
      wrap.style.minHeight = "";
      cfg.onImageSize?.(this.src, img.naturalWidth, img.naturalHeight);
    });
    wrap.appendChild(img);
    const set = (u) => {
      if (u) img.src = u;
      else img.replaceWith(document.createTextNode(this.alt || this.src));
    };
    const r = cfg.getImageURL ? cfg.getImageURL(this.src) : null;
    if (typeof r === "string" || r == null) set(r);
    else Promise.resolve(r).then(set).catch(() => set(null));
    return wrap;
  }
  ignoreEvent() { return true; }
}

class BulletWidget extends WidgetType {
  eq() { return true; }
  toDOM() {
    const sp = document.createElement("span");
    sp.className = "cm-md-bullet";
    sp.textContent = "•";
    return sp;
  }
}

// タスクリスト `- [ ]` / `- [x]` のチェックボックス。クリックで [ ] と [x] を切り替える。
class TaskWidget extends WidgetType {
  constructor(checked, pos) {
    super();
    this.checked = checked;
    this.pos = pos; // `[` と `]` の間の 1 文字の位置
  }
  eq(o) { return o.checked === this.checked && o.pos === this.pos; }
  toDOM() {
    const cb = document.createElement("input");
    cb.type = "checkbox";
    cb.className = "cm-md-task";
    cb.checked = this.checked;
    cb.disabled = false;
    cb.addEventListener("mousedown", (e) => { e.preventDefault(); }); // 編集は Vim で行う（mx）
    return cb;
  }
  ignoreEvent() { return true; }
}

const RE = {
  bullet: /^(\s*)([-*+])\s+(\[([ xX])\]\s+)?/,
  ordered: /^(\s*)(\d+[.)])\s+/,
  fence: /^\s*(```|~~~)/,
  heading: /^(#{1,6})\s+/,
  quote: /^(\s*>+\s?)/,
  hr: /^\s*([-*_])(?:\s*\1){2,}\s*$/,
  code: /`([^`\n]+)`/g,
  image: /!\[((?:\\.|[^\]\\])*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g,
  htmlimg: /<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["'][^>]*>/gi,
  link: /\[((?:\\.|[^\]\\])*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g,
  bold: /\*\*([^*\n]+)\*\*|__([^_\n]+)__/g,
  italic: /(?<![*_])\*([^*\n]+)\*(?!\*)|(?<![*_])_([^_\n]+)_(?!_)/g,
  strike: /~~([^~\n]+)~~/g,
};

function overlaps(occ, a, b) {
  for (const [x, y] of occ) if (a < y && x < b) return true;
  return false;
}

function decorateLine(line, active, inFence, decos, cfg) {
  const text = line.text;
  const base = line.from;
  const occ = [];

  // コードブロックの中身は記法を解釈せず、等幅の背景だけ付ける
  if (inFence) {
    // ``` の行は小さく薄く、中身は等幅の背景
    decos.push(Decoration.line({ class: RE.fence.test(text) ? "cm-md-fence cm-md-fence-edge" : "cm-md-fence" }).range(base));
    return;
  }

  // 中身が空の ParentBranch / ChildBranch / Context / Group / Related / BackLink の見出しは出さない（カーソルがあるときは出す）
  if (!active && cfg.emptySections?.has(line.number)) {
    decos.push(Decoration.line({ class: "cm-md-sec-empty" }).range(base));
    if (text.length > 0) decos.push(Decoration.replace({}).range(base, base + text.length));
    return;
  }

  const h = RE.heading.exec(text);
  if (h) {
    decos.push(Decoration.line({ class: `cm-md-h${Math.min(h[1].length, 6)}` }).range(base));
    if (!active) {
      occ.push([0, h[0].length]);
      decos.push(Decoration.replace({}).range(base, base + h[0].length));
    }
  }
  const q = RE.quote.exec(text);
  if (q) {
    decos.push(Decoration.line({ class: "cm-md-quote" }).range(base));
    if (!active) {
      occ.push([0, q[0].length]);
      decos.push(Decoration.replace({}).range(base, base + q[0].length));
    }
  }
  if (RE.hr.test(text)) {
    decos.push(Decoration.line({ class: "cm-md-hr" }).range(base));
    if (!active && text.length > 0) decos.push(Decoration.replace({}).range(base, base + text.length));
  }

  // 箇条書き: 行頭の `-` `*` `+` を • に、`- [ ]` はチェックボックスにする
  const b = RE.bullet.exec(text);
  if (b && !RE.hr.test(text)) {
    decos.push(Decoration.line({ class: "cm-md-li" }).range(base));
    if (!active) {
      const ind = b[1].length;
      if (b[3]) {
        const checked = b[4].toLowerCase() === "x";
        const end = b[0].length;
        occ.push([ind, end]);
        decos.push(Decoration.replace({ widget: new TaskWidget(checked, base + ind + 3) }).range(base + ind, base + end));
        if (checked) decos.push(Decoration.mark({ class: "cm-md-task-done" }).range(base + end, base + text.length));
      } else {
        occ.push([ind, ind + 1]);
        decos.push(Decoration.replace({ widget: new BulletWidget() }).range(base + ind, base + ind + 1));
      }
    }
  } else if (RE.ordered.test(text)) {
    decos.push(Decoration.line({ class: "cm-md-li" }).range(base));
  }

  const addSpan = (re, handler) => {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(text)) !== null) {
      const a = m.index;
      const b = a + m[0].length;
      if (overlaps(occ, a, b)) continue;
      occ.push([a, b]);
      handler(m, a, b);
    }
  };

  if (!active) addSpan(RE.code, (m, a, b) => {
    decos.push(Decoration.mark({ class: "cm-md-code" }).range(base + a + 1, base + b - 1));
    decos.push(Decoration.replace({}).range(base + a, base + a + 1));
    decos.push(Decoration.replace({}).range(base + b - 1, base + b));
  });

  addSpan(RE.image, (m, a, b) => {
    // 編集中（インサートモード）は、画像も文字（`![](…)`）のまま見せる。範囲は占有されるので
    // リンクとしても描かれない。
    if (active || cfg.insertMode) return;
    decos.push(Decoration.replace({ widget: new ImageWidget(m[1], m[2], cfg) }).range(base + a, base + b));
  });

  addSpan(RE.htmlimg, (m, a, b) => {
    if (active || cfg.insertMode) return;
    const w = /\bwidth\s*=\s*["']?(\d+(?:\.\d+)?)(%|px)?/i.exec(m[0]);
    const width = w ? w[1] + (w[2] || "px") : "";
    decos.push(Decoration.replace({ widget: new ImageWidget("", m[1], cfg, width) }).range(base + a, base + b));
  });

  addSpan(RE.link, (m, a, b) => {
    const disp = m[1];
    const tg = m[2];
    const dispStart = base + a + 1;
    const dispEnd = dispStart + disp.length;
    // `ノート.md#見出し` のようにアンカー（#…）が付いたリンクも、ノートへのリンクとして扱う
    const isMd = tg.split("#")[0].toLowerCase().endsWith(".md");
    decos.push(Decoration.mark({
      class: isMd ? "cm-md-link cm-md-link-md" : "cm-md-link",
      attributes: isMd ? { "data-md-href": tg } : {},
    }).range(dispStart, dispEnd));
    if (!cfg.linkSource) {
      decos.push(Decoration.replace({}).range(base + a, dispStart));
      decos.push(Decoration.replace({}).range(dispEnd, base + b));
    }
  });

  if (!active) addSpan(RE.strike, (m, a, b) => {
    const inner = m[1];
    const s = base + a + 2;
    decos.push(Decoration.mark({ class: "cm-md-strike" }).range(s, s + inner.length));
    decos.push(Decoration.replace({}).range(base + a, s));
    decos.push(Decoration.replace({}).range(s + inner.length, base + b));
  });

  if (!active) addSpan(RE.bold, (m, a, b) => {
    const inner = m[1] || m[2];
    const s = base + a + 2;
    decos.push(Decoration.mark({ class: "cm-md-bold" }).range(s, s + inner.length));
    decos.push(Decoration.replace({}).range(base + a, s));
    decos.push(Decoration.replace({}).range(s + inner.length, base + b));
  });

  if (!active) addSpan(RE.italic, (m, a, b) => {
    const inner = m[1] || m[2];
    const s = base + a + 1;
    decos.push(Decoration.mark({ class: "cm-md-em" }).range(s, s + inner.length));
    decos.push(Decoration.replace({}).range(base + a, s));
    decos.push(Decoration.replace({}).range(s + inner.length, base + b));
  });
}


// ノートの関係の節（ParentBranch: / ChildBranch: / Context: / Group: / Related: / BackLink:。旧 `### 名前` も）のうち、
// 中身（空行でない行）が無いものの見出しの行番号。コードブロックの中は見ない。
const SECTION_HEAD_RE = /^(?:###\s+(?:ParentBranch|ChildBranch|Context|Group|Related|BackLink|Parent)|(?:ParentBranch|ChildBranch|Context|Group|Related|BackLink):)\s*$/;
function emptySectionLines(doc, fmEnd) {
  const out = new Set();
  let inFence = false;
  let head = 0;
  let hasContent = false;
  const flush = () => { if (head && !hasContent) out.add(head); head = 0; hasContent = false; };
  for (let n = fmEnd + 1; n <= doc.lines; n++) {
    const t = doc.line(n).text;
    if (RE.fence.test(t)) { inFence = !inFence; if (head) hasContent = true; continue; }
    if (inFence) { if (head) hasContent = true; continue; }
    if (SECTION_HEAD_RE.test(t.trim())) { flush(); head = n; continue; }
    if (/^#{1,6}\s/.test(t)) { flush(); continue; }
    if (head && t.trim() !== "") hasContent = true;
  }
  flush();
  return out;
}

function buildDecorations(view, cfg) {
  const doc = view.state.doc;
  const decos = [];
  // Vim のモード（インサート中は画像を文字のまま見せる）
  const vmode = view.state.field(vimField, false)?.mode || "n";
  cfg.insertMode = !cfg.viewOnly && (vmode[0] === "i" || vmode[0] === "R");
  // 先頭の front matter（--- で囲まれた部分）。カーソルがあるときは通常どおり、無いときは薄く小さく。
  let fmEnd = 0;
  if (doc.lines >= 2 && doc.line(1).text.trim() === "---") {
    for (let n = 2; n <= doc.lines; n++) {
      if (doc.line(n).text.trim() === "---") { fmEnd = n; break; }
    }
  }
  if (fmEnd) {
    // YAML（front matter）は畳まず、小さな等幅で常に表示する
    const cls = "cm-md-fm";
    for (let n = 1; n <= fmEnd; n++) decos.push(Decoration.line({ class: cls }).range(doc.line(n).from));
  }
  cfg.emptySections = emptySectionLines(doc, fmEnd);
  const activeLines = new Set();
  // ``` で囲まれたコードブロックの行番号（開始・終了の行を含む）
  const fenceLines = new Set();
  let inBlock = false;
  for (let n = 1; n <= doc.lines; n++) {
    const t = doc.line(n).text;
    if (RE.fence.test(t)) { fenceLines.add(n); inBlock = !inBlock; }
    else if (inBlock) fenceLines.add(n);
  }
  if (!cfg.viewOnly) for (const r of view.state.selection.ranges) {
    const a = doc.lineAt(r.from).number;
    const b = doc.lineAt(r.to).number;
    for (let l = a; l <= b; l++) activeLines.add(l);
  }
  for (const { from, to } of view.visibleRanges) {
    let pos = from;
    while (pos <= to) {
      const line = doc.lineAt(pos);
      if (line.number <= fmEnd) { if (line.to + 1 > to) break; pos = line.to + 1; continue; }
      decorateLine(line, activeLines.has(line.number), fenceLines.has(line.number), decos, cfg);
      if (line.to + 1 > to) break;
      pos = line.to + 1;
    }
  }
  return Decoration.set(decos, true);
}

// 画像の大きさが分かったとき、装飾（と画像の高さの見積もり）を作り直させる
const refreshDecorations = StateEffect.define();

function livePreview(cfg) {
  return ViewPlugin.fromClass(class {
    constructor(view) { this.decorations = buildDecorations(view, cfg); }
    update(u) {
      const modeChanged = u.startState.field(vimField, false)?.mode !== u.state.field(vimField, false)?.mode;
      if (u.docChanged || u.selectionSet || u.viewportChanged || modeChanged || u.transactions.some((tr) => tr.effects.some((e) => e.is(refreshDecorations)))) {
        this.decorations = buildDecorations(u.view, cfg);
      }
    }
  }, {
    decorations: (v) => v.decorations,
    provide: (plugin) => EditorView.atomicRanges.of((view) => view.plugin(plugin)?.decorations || Decoration.none),
  });
}



// ---------------------------------------------------------------- 表（テーブル）

// `| a | b |` の行 + `| --- | --- |` の行 + 続く行を、本物の表として描く。カーソルが表の中にあるとき
// （とインサート中）は、編集できるよう文字のまま見せる。ブロックの置き換えなので StateField で出す。
function splitRow(text) {
  let t = text.trim();
  if (t.startsWith("|")) t = t.slice(1);
  if (t.endsWith("|") && !t.endsWith("\\|")) t = t.slice(0, -1);
  return t.split(/(?<!\\)\|/).map((c) => c.trim().replace(/\\\|/g, "|"));
}
const DELIM_RE = /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?\s*$|^\s*\|\s*:?-+:?\s*\|?\s*$/;

function findTables(doc) {
  const out = [];
  let inFence = false;
  const n = doc.lines;
  let fmEnd = 0;
  if (n >= 2 && doc.line(1).text.trim() === "---") {
    for (let i = 2; i <= n; i++) if (doc.line(i).text.trim() === "---") { fmEnd = i; break; }
  }
  for (let i = fmEnd + 1; i <= n; i++) {
    const t = doc.line(i).text;
    if (RE.fence.test(t)) { inFence = !inFence; continue; }
    if (inFence || !t.includes("|") || i === n) continue;
    if (!DELIM_RE.test(doc.line(i + 1).text)) continue;
    const head = splitRow(t);
    const aligns = splitRow(doc.line(i + 1).text).map((c) => (c.startsWith(":") && c.endsWith(":") ? "center" : c.endsWith(":") ? "right" : c.startsWith(":") ? "left" : ""));
    if (head.length !== aligns.length) continue;
    const rows = [];
    let j = i + 2;
    while (j <= n && doc.line(j).text.trim() !== "" && doc.line(j).text.includes("|") && !RE.fence.test(doc.line(j).text)) {
      rows.push(splitRow(doc.line(j).text));
      j++;
    }
    out.push({ from: doc.line(i).from, to: doc.line(j - 1).to, startLine: i, endLine: j - 1, head, aligns, rows });
    i = j - 1;
  }
  return out;
}

function inlineInto(el, text) {
  const re = /\*\*([^*]+)\*\*|`([^`]+)`|\[((?:\\.|[^\]\\])*)\]\(([^)\s]+)\)/g;
  let last = 0, m;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) el.appendChild(document.createTextNode(text.slice(last, m.index)));
    let n;
    if (m[1] != null) { n = document.createElement("strong"); n.textContent = m[1]; }
    else if (m[2] != null) { n = document.createElement("code"); n.className = "cm-md-code"; n.textContent = m[2]; }
    else { n = document.createElement("span"); n.className = "cm-md-link"; n.textContent = m[3] || m[4]; }
    el.appendChild(n);
    last = m.index + m[0].length;
  }
  if (last < text.length) el.appendChild(document.createTextNode(text.slice(last)));
}

class TableWidget extends WidgetType {
  constructor(t) { super(); this.t = t; this.key = JSON.stringify([t.head, t.aligns, t.rows]); }
  eq(o) { return o.key === this.key; }
  toDOM() {
    const { head, aligns, rows } = this.t;
    const wrap = document.createElement("div");
    wrap.className = "cm-md-tablewrap";
    const table = document.createElement("table");
    table.className = "cm-md-table";
    const mk = (tag, cells, tr) => {
      for (let c = 0; c < head.length; c++) {
        const cell = document.createElement(tag);
        if (aligns[c]) cell.style.textAlign = aligns[c];
        inlineInto(cell, cells[c] ?? "");
        tr.appendChild(cell);
      }
    };
    const thead = document.createElement("thead");
    const htr = document.createElement("tr");
    mk("th", head, htr);
    thead.appendChild(htr);
    table.appendChild(thead);
    const tbody = document.createElement("tbody");
    for (const r of rows) { const tr = document.createElement("tr"); mk("td", r, tr); tbody.appendChild(tr); }
    table.appendChild(tbody);
    wrap.appendChild(table);
    return wrap;
  }
  ignoreEvent() { return false; }
}

function tableField(cfg) {
  const build = (state) => {
    const doc = state.doc;
    const vmode = state.field(vimField, false)?.mode || "n";
    const editing = !cfg.viewOnly && (vmode[0] === "i" || vmode[0] === "R");
    const sel = state.selection.main;
    const a = doc.lineAt(sel.from).number, b = doc.lineAt(sel.to).number;
    const decos = [];
    for (const t of findTables(doc)) {
      if (!cfg.viewOnly && (editing || (a <= t.endLine && b >= t.startLine))) continue;
      decos.push(Decoration.replace({ widget: new TableWidget(t), block: true }).range(t.from, t.to));
    }
    return Decoration.set(decos, true);
  };
  return StateField.define({
    create: (state) => build(state),
    update(v, tr) {
      const vm = (st) => st.field(vimField, false)?.mode;
      if (tr.docChanged || tr.selection || vm(tr.startState) !== vm(tr.state) || tr.effects.some((e) => e.is(refreshDecorations))) return build(tr.state);
      return v;
    },
    provide: (f) => EditorView.decorations.from(f),
  });
}


// 見るだけモードで検索したとき、見つけた行をうっすら色づける
const setHit = StateEffect.define();
const hitField = StateField.define({
  create: () => null,
  update(v, tr) {
    if (tr.docChanged) v = null;
    for (const e of tr.effects) if (e.is(setHit)) v = e.value;
    return v;
  },
  provide: (f) => EditorView.decorations.compute([f], (state) => {
    const n = state.field(f);
    if (!n || n > state.doc.lines) return Decoration.none;
    return Decoration.set([Decoration.line({ class: "cm-vim-hit" }).range(state.doc.line(n).from)]);
  }),
});

// ---------------------------------------------------------------- Vim のカーソルと選択

// Vim の状態（カーソル位置・モード・ビジュアル範囲）。表示だけに使う。
const setVim = StateEffect.define();
// GUI 編集モード（アプリの編集モード）か。このときは Vim の状態ではなく、CodeMirror 自身の選択が「カーソル」。
const guiMode = Facet.define({ combine: (v) => v.some(Boolean) });
// プログラムによる変更（読み込み・外の変更の取り込み）の印。ユーザーの編集（元に戻す履歴・自動保存の対象）と区別する。
const external = Annotation.define();
const vimField = StateField.define({
  create: () => ({ pos: 0, mode: "n", visFrom: null, visTo: null }),
  update(v, tr) {
    if (tr.state.facet(guiMode)) {
      // 編集中はカーソルのある行の記法を見せる（インサートと同じ見え方）。選択範囲はブラウザの選択表示に任せる
      const h = tr.newSelection.main.head;
      return v.pos === h && v.mode === "i" && v.visFrom == null ? v : { pos: h, mode: "i", visFrom: null, visTo: null };
    }
    for (const e of tr.effects) if (e.is(setVim)) return e.value;
    return v;
  },
});

// 仮想テキスト（Vim のテキストプロパティ）: [lnum, col(バイト), text, type]。リンクの数字のしるしなど。
const setVtext = StateEffect.define();
const vtextField = StateField.define({
  create: () => [],
  update(v, tr) {
    for (const e of tr.effects) if (e.is(setVtext)) return e.value;
    return v;
  },
});

class VTextWidget extends WidgetType {
  constructor(text, type) { super(); this.text = text; this.type = type; }
  eq(o) { return o.text === this.text && o.type === this.type; }
  toDOM() {
    const s = document.createElement("span");
    s.className = "cm-vtext cm-vtext-" + String(this.type).replace(/[^A-Za-z0-9_-]/g, "");
    s.textContent = this.text.replace(/ /g, "\u00a0");
    return s;
  }
  ignoreEvent() { return true; }
}

// 依存に "doc" を入れる（文書が入れ替わったとき、前の文書の位置の装飾を残さない）
const vtextDecorations = EditorView.decorations.compute(["doc", vtextField], (state) => {
  const decos = [];
  const doc = state.doc;
  for (const [lnum, col, text, type] of state.field(vtextField)) {
    if (lnum < 1 || lnum > doc.lines) continue;
    const ln = doc.line(lnum);
    decos.push(Decoration.widget({ widget: new VTextWidget(text, type), side: -1 }).range(ln.from + byteColToIndex(ln.text, col)));
  }
  return Decoration.set(decos, true);
});

class CursorWidget extends WidgetType {
  constructor(kind) { super(); this.kind = kind; }
  eq(o) { return o.kind === this.kind; }
  toDOM() {
    const s = document.createElement("span");
    s.className = "cm-vim-" + this.kind;
    if (this.kind === "block") s.textContent = " ";
    return s;
  }
}

const vimDecorations = EditorView.decorations.compute(["doc", vimField], (state) => {
  const v = state.field(vimField);
  const decos = [];
  const doc = state.doc;
  const pos = Math.min(v.pos, doc.length);
  if (v.visFrom != null) {
    const from = Math.max(0, Math.min(v.visFrom, v.visTo)), to = Math.min(doc.length, Math.max(v.visFrom, v.visTo));
    if (to > from) decos.push(Decoration.mark({ class: "cm-vim-visual" }).range(from, to));
  }
  const insertLike = v.mode[0] === "i" || v.mode[0] === "R";
  if (insertLike) {
    decos.push(Decoration.widget({ widget: new CursorWidget(v.mode[0] === "R" ? "under" : "bar"), side: -1 }).range(pos));
  } else if (pos < doc.length && doc.sliceString(pos, pos + 1) !== "\n") {
    decos.push(Decoration.mark({ class: "cm-vim-block" }).range(pos, Math.min(doc.length, pos + 1)));
  } else {
    decos.push(Decoration.widget({ widget: new CursorWidget("block"), side: 1 }).range(pos));
  }
  return Decoration.set(decos, true);
});

// Vim の col（1 始まりのバイト位置）を、文字列の添字（UTF-16）に直す
function byteColToIndex(text, col) {
  const target = Math.max(0, col - 1);
  let bytes = 0, idx = 0;
  for (const ch of text) {
    if (bytes >= target) break;
    const c = ch.codePointAt(0);
    bytes += c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4;
    idx += ch.length;
  }
  return idx;
}

const mdHighlight = HighlightStyle.define([
  { tag: tags.heading, fontWeight: "700" },
  { tag: tags.strong, fontWeight: "700" },
  { tag: tags.emphasis, fontStyle: "italic" },
  { tag: tags.link, color: "var(--link)" },
  { tag: tags.url, color: "var(--link)" },
  { tag: tags.comment, color: "var(--fg-dim)" },
  { tag: tags.quote, color: "var(--fg-dim)" },
]);

export function createView(opts) {
  const cfg = { getImageURL: opts.getImageURL || (() => null), getImageSize: opts.getImageSize, onImageSize: opts.onImageSize, listNotes: () => [] };
  // 読み取り専用（Vim の内容を映す）と、GUI 編集の切り替え
  const editableC = new Compartment();
  const readOnlyExt = [EditorView.editable.of(false), EditorState.readOnly.of(true)];
  const editExt = [EditorView.editable.of(true), EditorState.readOnly.of(false), guiMode.of(true)];
  const guiKeys = (id) => (view) => { if (!view.state.facet(guiMode)) return false; return opts.onCommand ? opts.onCommand(id) !== false : false; };
  const state = EditorState.create({
    doc: "",
    extensions: [
      editableC.of(readOnlyExt),
      // GUI 編集のキー（編集モードのときだけ効く。ボタン・メニューと同じコマンド ID を呼ぶ）
      Prec.highest(keymap.of([
        { key: "Mod-z", run: guiKeys("undo"), preventDefault: true },
        { key: "Mod-y", run: guiKeys("redo"), preventDefault: true },
        { key: "Mod-Shift-z", run: guiKeys("redo"), preventDefault: true },
        { key: "Mod-s", run: guiKeys("save"), preventDefault: true },
        { key: "Mod-b", run: guiKeys("bold"), preventDefault: true },
        { key: "Mod-i", run: guiKeys("italic"), preventDefault: true },
        { key: "Mod-e", run: guiKeys("code"), preventDefault: true },
        { key: "Mod-k", run: guiKeys("link"), preventDefault: true },
        { key: "Enter", run: guiKeys("enter") },
        { key: "Tab", run: guiKeys("indent") },
        { key: "Shift-Tab", run: guiKeys("outdent") },
      ])),
      EditorView.updateListener.of((u) => {
        if (!u.docChanged || !u.state.facet(guiMode)) return;
        if (u.transactions.some((tr) => tr.annotation(external))) return;
        opts.onUserChange?.(u);
      }),
      EditorView.lineWrapping,
      markdown({ base: markdownLanguage }),
      syntaxHighlighting(mdHighlight),
      vimField,
      vimDecorations,
      vtextField,
      vtextDecorations,
      livePreview(cfg),
      tableField(cfg),
      hitField,
      EditorView.domEventHandlers({
        mousedown: (e, view) => {
          const el = e.target?.closest?.("[data-md-href]");
          const pos = view.posAtCoords({ x: e.clientX, y: e.clientY });
          opts.onClick?.({ pos, link: !!el, href: el ? el.getAttribute("data-md-href") : "", doc: view.state.doc, alt: e.altKey, mod: e.ctrlKey || e.metaKey, event: e });
          return false;
        },
      }),
      EditorView.theme({
        "&": { fontSize: "var(--content-font-size, 16px)", height: "100%" },
        // Obsidian の「行の長さを制限」（700px）と行間 1.5
        ".cm-content": { padding: "32px 32px 40vh", maxWidth: "calc(var(--line-width, 700px) + 64px)", margin: "0 auto" },
        ".cm-scroller": { fontFamily: "var(--font-body)", lineHeight: "1.5" },
        ".cm-gutters": { display: "none" },
        "&.cm-focused": { outline: "none" },
      }),
    ],
  });
  const view = new EditorView({ state, parent: opts.parent });

  const api = {
    view,
    getText: () => view.state.doc.toString(),
    isComposing: () => !!(view.composing || view.compositionStarted),   // 日本語入力の変換中
    // GUI 編集モードの入り切り。入ると編集できる状態になり、Vim の状態の反映（カーソル・ビジュアル）はやめる
    setEditable(on) {
      this.editing = !!on;
      view.dispatch({ effects: editableC.reconfigure(on ? editExt : readOnlyExt) });
      if (!on) view.dispatch({ effects: setVim.of({ pos: view.state.selection.main.head, mode: "n", visFrom: null, visTo: null }) });
    },
    isEditing: () => !!api.editing,
    focus: () => view.focus(),
    selection: () => { const r = view.state.selection.main; return { from: r.from, to: r.to, anchor: r.anchor, head: r.head }; },
    // editcmds.js の結果（{changes, anchor, head}）を適用する。ユーザーの編集として扱う（履歴・自動保存の対象）
    applyEdit(result) {
      if (!result) return false;
      view.dispatch({ changes: result.changes, selection: { anchor: result.anchor, head: result.head }, scrollIntoView: true, userEvent: "input" });
      view.focus();
      return true;
    },
    // 履歴の取り消し・やり直しで文書全体を入れ替える（変わったところだけ差し替え、カーソルはその末尾へ）。
    // ユーザーの編集として扱わない（履歴に積まない・自動保存の「変更」として数えるのは呼び出し側）
    replaceAll(text) {
      const cur = view.state.doc.toString();
      if (cur === text) return;
      let a = 0;
      const max = Math.min(cur.length, text.length);
      while (a < max && cur.charCodeAt(a) === text.charCodeAt(a)) a++;
      let b = 0;
      while (b < max - a && cur.charCodeAt(cur.length - 1 - b) === text.charCodeAt(text.length - 1 - b)) b++;
      const insert = text.slice(a, text.length - b);
      view.dispatch({ changes: { from: a, to: cur.length - b, insert }, selection: { anchor: a + insert.length }, annotations: external.of(true), scrollIntoView: true });
    },
    // 位置 pos にあるマークダウンのリンク [表示](先) の先（無ければ ""）。編集中の行（記法が見えている行）でリンクを開くのに使う
    linkAt(pos) {
      const line = view.state.doc.lineAt(pos);
      const re = /\[(?:\\.|[^\]\\])*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g;
      let m;
      while ((m = re.exec(line.text)) !== null) {
        if (pos >= line.from + m.index && pos <= line.from + m.index + m[0].length) return m[1];
      }
      return "";
    },
    // 変わったところだけ差し替える（スクロールや選択を乱さない）
    setText(text) {
      const cur = view.state.doc.toString();
      if (cur === text) return;
      let a = 0;
      const max = Math.min(cur.length, text.length);
      while (a < max && cur.charCodeAt(a) === text.charCodeAt(a)) a++;
      let b = 0;
      while (b < max - a && cur.charCodeAt(cur.length - 1 - b) === text.charCodeAt(text.length - 1 - b)) b++;
      view.dispatch({ changes: { from: a, to: cur.length - b, insert: text.slice(a, text.length - b) }, annotations: external.of(true) });
    },
    setLinkSource(on) {
      if (cfg.linkSource === !!on) return;
      cfg.linkSource = !!on;
      view.dispatch({ effects: refreshDecorations.of(null) });
    },
    // 見るだけ: カーソルのある行も含め、全部を描いた見た目にする。カーソルへのスクロールもしない
    setViewOnly(on) {
      cfg.viewOnly = !!on;
      this.followCursor = !on;
      view.dispatch({ effects: refreshDecorations.of(null) });
    },
    // カーソルのある行を真ん中へスクロールして色づける（見るだけモードで検索したあと）。null で色を消す
    revealCursor(on = true) {
      const head = view.state.selection.main.head;
      view.dispatch({ effects: on ? [setHit.of(view.state.doc.lineAt(head).number)] : [setHit.of(null)] });
      if (!on) return;
      // 行の位置は、画像の高さが分かるたびに変わるので、描き終わるまで何度か合わせ直す
      const go = () => {
        const sc = view.scrollDOM;
        const top = view.lineBlockAt(head).top;
        sc.scrollTop = Math.max(0, top - sc.clientHeight / 2 + 32);
      };
      go();
      requestAnimationFrame(() => { go(); setTimeout(go, 150); });
    },
    // 画像の大きさが分かったので、高さの見積もりを取り直す
    refresh() { view.dispatch({ effects: refreshDecorations.of(null) }); },
    // 仮想テキスト（リンクの数字のしるしなど）を反映する
    setVtext(list) {
      view.dispatch({ effects: setVtext.of(list || []) });
    },
    // Vim のカーソル（行・バイト列）、モード、ビジュアルの始点を反映する
    setVim({ cur, mode, vis }) {
      const doc = view.state.doc;
      const lineOf = (l) => doc.line(Math.min(Math.max(1, l), doc.lines));
      const idxOf = (l, col) => { const ln = lineOf(l); return ln.from + byteColToIndex(ln.text, col); };
      const pos = idxOf(cur[0], cur[1]);
      let visFrom = null, visTo = null;
      if (vis && mode[0] !== "n") {
        const vp = idxOf(vis[0], vis[1]);
        if (mode[0] === "V") {
          const a = lineOf(Math.min(vis[0], cur[0])), b = lineOf(Math.max(vis[0], cur[0]));
          visFrom = a.from; visTo = Math.min(doc.length, b.to + 1);
        } else {
          visFrom = Math.min(vp, pos); visTo = Math.max(vp, pos) + 1;
        }
      }
      view.dispatch({
        selection: { anchor: pos },
        effects: [setVim.of({ pos, mode, visFrom, visTo }), ...(this.followCursor === false ? [] : [EditorView.scrollIntoView(pos, { y: "nearest", yMargin: 90 })])],
      });
    },
    lineColAt(pos) {
      const ln = view.state.doc.lineAt(pos);
      let bytes = 1;
      for (const ch of ln.text.slice(0, pos - ln.from)) {
        const c = ch.codePointAt(0);
        bytes += c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4;
      }
      return [ln.number, bytes];
    },
  };
  return api;
}
