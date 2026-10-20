// GUI 編集モードの書式コマンド（DOM に触れない純関数）。ボタン・メニュー・キーが同じ関数を呼ぶ。
// どれも (doc, 選択) を受け取り、{ changes: [{from, to, insert}], anchor, head } を返す（CodeMirror の dispatch にそのまま使える）。
// 変更が無いときは null。doc は文字列、位置は UTF-16 の添字。

function lineStart(doc, pos) { const i = doc.lastIndexOf("\n", pos - 1); return i < 0 ? 0 : i + 1; }
function lineEnd(doc, pos) { const i = doc.indexOf("\n", pos); return i < 0 ? doc.length : i; }

// 選択を open/close で囲む。すでに囲まれていれば外す。選択が空なら記号だけ入れて間にカーソルを置く。
export function toggleWrap(doc, from, to, open, close = open) {
  const before = doc.slice(Math.max(0, from - open.length), from);
  const after = doc.slice(to, to + close.length);
  if (from !== to && before === open && after === close) {         // 選択の外側が記号 → 外す
    return { changes: [{ from: from - open.length, to: from, insert: "" }, { from: to, to: to + close.length, insert: "" }], anchor: from - open.length, head: to - open.length };
  }
  const sel = doc.slice(from, to);
  if (from !== to && sel.startsWith(open) && sel.endsWith(close) && sel.length >= open.length + close.length) {   // 選択の内側が記号 → 外す
    const inner = sel.slice(open.length, sel.length - close.length);
    return { changes: [{ from, to, insert: inner }], anchor: from, head: from + inner.length };
  }
  if (from === to) return { changes: [{ from, to, insert: open + close }], anchor: from + open.length, head: from + open.length };
  return { changes: [{ from, to, insert: open + sel + close }], anchor: from + open.length, head: from + open.length + sel.length };
}

// 見出し: その行を `#`×level の見出しにする。すでに同じレベルなら普通の行に戻す。別のレベルなら付け替える。
export function setHeading(doc, pos, level) {
  const a = lineStart(doc, pos), b = lineEnd(doc, pos);
  const line = doc.slice(a, b);
  const m = /^(#{1,6})\s+/.exec(line);
  const prefix = "#".repeat(level) + " ";
  let insert, delta;
  if (m && m[1].length === level) { insert = line.slice(m[0].length); delta = -m[0].length; }
  else if (m) { insert = prefix + line.slice(m[0].length); delta = prefix.length - m[0].length; }
  else { insert = prefix + line; delta = prefix.length; }
  const p = Math.max(a, pos + delta);
  return { changes: [{ from: a, to: b, insert }], anchor: p, head: p };
}

const PREFIXES = { bullet: /^(\s*)[-*+]\s+(?!\[[ xX]\])/, task: /^(\s*)[-*+]\s+\[[ xX]\]\s+/, quote: /^(\s*)>\s?/, number: /^(\s*)\d+[.)]\s+/ };
const MAKE = { bullet: (ind) => ind + "- ", task: (ind) => ind + "- [ ] ", quote: (ind) => ind + "> ", number: (ind, n) => ind + (n + 1) + ". " };

// 選択に掛かる全部の行に、箇条書き・チェックボックス・引用・番号つきを付ける。全部の行にすでに付いていれば外す。
export function toggleLinePrefix(doc, from, to, kind) {
  const re = PREFIXES[kind];
  const a = lineStart(doc, from), b = lineEnd(doc, to > from && doc[to - 1] === "\n" ? to - 1 : to);
  const lines = doc.slice(a, b).split("\n");
  const allHave = lines.filter((l) => l.trim()).every((l) => re.test(l));
  const out = lines.map((l, i) => {
    if (!l.trim()) return l;
    if (allHave) return l.replace(re, "$1");
    const stripped = l.replace(PREFIXES.bullet, "$1").replace(PREFIXES.task, "$1").replace(PREFIXES.number, "$1").replace(PREFIXES.quote, "$1");
    const ind = /^\s*/.exec(stripped)[0];
    return MAKE[kind](ind, i) + stripped.slice(ind.length);
  });
  const insert = out.join("\n");
  if (insert === doc.slice(a, b)) return null;
  return { changes: [{ from: a, to: b, insert }], anchor: a, head: a + insert.length };
}

// チェックボックスの [ ] と [x] を切り替える（その行にチェックボックスが無ければ null）
export function toggleTaskAt(doc, pos) {
  const a = lineStart(doc, pos), b = lineEnd(doc, pos);
  const line = doc.slice(a, b);
  const m = /^(\s*[-*+]\s+\[)([ xX])(\])/.exec(line);
  if (!m) return null;
  const at = a + m[1].length;
  return { changes: [{ from: at, to: at + 1, insert: m[2] === " " ? "x" : " " }], anchor: pos, head: pos };
}

// 選択を [選択](url) にする。選択が空なら [](url) を入れて文字の位置にカーソルを置く。
export function makeLink(doc, from, to, url) {
  const sel = doc.slice(from, to);
  const insert = `[${sel}](${url})`;
  const inner = from + 1;
  return { changes: [{ from, to, insert }], anchor: sel ? from + insert.length : inner, head: sel ? from + insert.length : inner };
}

// 変更を文字列に適用する（試験・履歴用。CodeMirror は自分で適用する）
export function apply(doc, result) {
  if (!result) return doc;
  const ch = [...result.changes].sort((x, y) => y.from - x.from);
  let out = doc;
  for (const c of ch) out = out.slice(0, c.from) + c.insert + out.slice(c.to);
  return out;
}

// Enter: 箇条書き・番号・チェックボックスの行の末尾なら、次の項目を作る。中身が空の項目で押したら、項目をやめる。
// リストでなければ null（ふつうの改行は CodeMirror に任せる）。
export function enterInList(doc, pos) {
  const a = lineStart(doc, pos), b = lineEnd(doc, pos);
  if (pos !== b) return null;                                       // 行の途中の Enter は普通の改行
  const line = doc.slice(a, b);
  const m = /^(\s*)([-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?(.*)$/.exec(line);
  if (!m) return null;
  if (m[4].trim() === "") {                                         // 空の項目 → 項目をやめる（その行を空にする）
    return { changes: [{ from: a, to: b, insert: m[1] }], anchor: a + m[1].length, head: a + m[1].length };
  }
  const bullet = /^\d/.test(m[2]) ? (parseInt(m[2], 10) + 1) + m[2].slice(-1) : m[2];
  const prefix = m[1] + bullet + " " + (m[3] ? "[ ] " : "");
  return { changes: [{ from: pos, to: pos, insert: "\n" + prefix }], anchor: pos + 1 + prefix.length, head: pos + 1 + prefix.length };
}

// Tab / Shift+Tab: 選択に掛かるリストの行を字下げ（dir=1）／字上げ（dir=-1）する。リストの行が無ければ null。
export function indentLines(doc, from, to, dir) {
  const a = lineStart(doc, from), b = lineEnd(doc, to);
  const lines = doc.slice(a, b).split("\n");
  let changed = false;
  const out = lines.map((l) => {
    if (!/^\s*([-*+]|\d+[.)])\s/.test(l)) return l;
    if (dir > 0) { changed = true; return "  " + l; }
    const m = /^( {1,2}|\t)/.exec(l);
    if (!m) return l;
    changed = true;
    return l.slice(m[0].length);
  });
  if (!changed) return null;
  const insert = out.join("\n");
  return { changes: [{ from: a, to: b, insert }], anchor: a, head: a + insert.length };
}
