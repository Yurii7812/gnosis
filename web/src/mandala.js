// 曼荼羅（タブ）。2 つの使い方:
//   ① 自分で作る曼荼羅: ふつうの Markdown ノート（front matter `mandala: true`）の 9×9 の表（python/mandala.py と同じ形）。
//      副題が 8 つで足りなくなったら、同じ主題の 9×9 が下に続く（同じノートの 2 枚目・3 枚目の表）。下へスクロールすれば次の曼荼羅。
//   ② 索引を曼荼羅で見る: 真ん中に索引の題、周りに索引の項目（8 つずつ。多ければ下に続く）、そのまわりに各項目のトピック索引の項目。
//      項目を押すとそのノートを Vim で開く。「この索引へ」でトピック索引を真ん中にして入っていく。空いた枠から索引にノートを足せる。
//   並び替え（表示だけ。ファイルは変えない）: ファイルの順・索引の順・あいうえお順・埋まっている順・空いている順・新しい順。
//   自分の曼荼羅では「この並びで保存」で、その順に表を書き直せる。
//   3×3: 各曼荼羅の中心のブロック（主題と 8 つの副題）を縦に並べる。副題の「広げる ▸」でそのブロックへ入る。9×9: 全部のマス。
//   副題は中心のブロックと周りのブロックの真ん中の 2 か所にある。片方を直せばもう片方も同じにする（mandala.py の sync と同じ対応）。
//   マスの文字から「ノートにする」「曼荼羅にする」（Vim の gnosis#app_op → mandala.py link-cell）。既存のノートは「既存…」かドラッグで。
//   保存は Vim（:write）。読んだときの内容と違えば、マスごとの 3-way で合わせて保存し直す。
import { h, button, toast, imeActive, form, noteSub } from "./ui.js";

const N = 9;
const RING = [[3, 3], [3, 4], [3, 5], [4, 5], [5, 5], [5, 4], [5, 3], [4, 3]];          // 上から時計回り
const BLOCK_CENTER = [[1, 1], [1, 4], [1, 7], [4, 7], [7, 7], [7, 4], [7, 1], [4, 1]];
const THEME = [4, 4];
const ROW_RE = /^\s*\|(.*)\|\s*$/;
const SEP_RE = /^\s*\|\s*:?-{2,}/;
const LINK_RE = /\[((?:\\.|[^\]\\])*)\]\(([^)\s]+)\)/;
// 3×3 の表示での、ブロックの中の位置 → ブロック番号（0..8）。4 が中心。副題 i のブロックは BLOCK_OF_RING[i]
const BLOCK_OF_RING = [0, 1, 2, 5, 8, 7, 6, 3];

export function cellsOf(line) {
  const m = ROW_RE.exec(line);
  const inner = m ? m[1] : line;
  return inner.split(/(?<!\\)\|/).map((c) => c.trim().replace(/\\\|/g, "|"));
}

const emptyGrid = () => Array.from({ length: N }, () => Array(N).fill(""));

// 曼荼羅の表（列名の行・区切りの行・マスの行）の [始まり, 終わり) の一覧（mandala.py の table_blocks と同じ）
export function tableBlocks(lines) {
  const out = [];
  let i = 0;
  while (i < lines.length) {
    if (ROW_RE.test(lines[i]) && i + 1 < lines.length && SEP_RE.test(lines[i + 1])) {
      let j = i + 2;
      while (j < lines.length && ROW_RE.test(lines[j]) && j - (i + 2) < N) j++;
      out.push([i, j]);
      i = j;
    } else i++;
  }
  return out;
}

function gridOf(lines, [a, b]) {
  const grid = emptyGrid();
  lines.slice(a + 2, b).slice(0, N).forEach((ln, r) => cellsOf(ln).slice(0, N).forEach((v, c) => { grid[r][c] = v; }));
  return grid;
}

// 全部の表（何枚目かの順）。表が無ければ空の 9×9 が 1 枚
export function parseGrids(text) {
  const lines = text.split("\n");
  const bl = tableBlocks(lines);
  return bl.length ? bl.map((b) => gridOf(lines, b)) : [emptyGrid()];
}

export function parseGrid(text) { return parseGrids(text)[0]; }

export function renderTable(grid) {
  const esc = (v) => v.replace(/\|/g, "\\|").replace(/\n/g, " ");
  const out = ["| " + Array.from({ length: N }, (_, c) => String(c + 1)).join(" | ") + " |", "|" + "---|".repeat(N)];
  for (let r = 0; r < N; r++) out.push("| " + grid[r].map(esc).join(" | ") + " |");
  return out;
}

// 本文の表を grids に差し替える（増えたら最後の表の下に空行をはさんで足し、減ったら消す）。表の外の本文は触らない。表が無ければ H1 の下に置く
export function replaceTables(text, grids) {
  const lines = text.split("\n");
  const bl = tableBlocks(lines);
  const tables = [];
  grids.forEach((g, k) => { if (k) tables.push(""); tables.push(...renderTable(g)); });
  if (!bl.length) {
    const h1 = lines.findIndex((l) => /^#\s/.test(l));
    lines.splice(h1 + 1, 0, "", ...tables);
    return lines.join("\n");
  }
  return [...lines.slice(0, bl[0][0]), ...tables, ...lines.slice(bl[bl.length - 1][1])].join("\n");
}

export function replaceTable(text, grid) {
  const all = parseGrids(text);
  all[0] = grid;
  return replaceTables(text, all);
}

// マスごとの 3-way: base（前に読んだ・保存した版）から、こちら（ours）とファイル（disk）のどちらが変えたか。
// 両方が違う文字に変えたマスは、こちらの文字にして数を返す
export function mergeGrids(base, ours, disk) {
  let clashes = 0;
  const grid = ours.map((row, r) => row.map((v, c) => {
    const b = base[r][c], d = disk[r][c];
    if (v === b) return d;
    if (d === b || d === v) return v;
    clashes++;
    return v;
  }));
  return { grid, clashes };
}

// 何枚もの表の 3-way（枚数が違うときは、ある方の表をそのまま使う）
export function mergePages(base, ours, disk) {
  let clashes = 0;
  const n = Math.max(ours.length, disk.length);
  const out = [];
  for (let p = 0; p < n; p++) {
    const o = ours[p], d = disk[p], b = base[p] || emptyGrid();
    if (o && d) { const m = mergeGrids(b, o, d); clashes += m.clashes; out.push(m.grid); }
    else out.push(o || d);
  }
  return { grids: out, clashes };
}

// マス (r, c) の対になるマス（副題の 2 か所）。無ければ null
export function mirrorOf(r, c) {
  for (let i = 0; i < 8; i++) {
    if (RING[i][0] === r && RING[i][1] === c) return BLOCK_CENTER[i];
    if (BLOCK_CENTER[i][0] === r && BLOCK_CENTER[i][1] === c) return RING[i];
  }
  return null;
}

// ブロック b（0..8）の 3×3 のマスの位置（行, 列）
const blockCells = (b) => { const br = Math.floor(b / 3) * 3, bc = (b % 3) * 3; const out = []; for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) out.push([br + r, bc + c]); return out; };

// 曼荼羅ノートのフォルダ（dir、vault からの相対・末尾 / 付き）から、ノート rel へのリンク先
export function relLink(dir, rel) {
  const from = dir.split("/").filter(Boolean), to = rel.split("/");
  let i = 0;
  while (i < from.length && i < to.length - 1 && from[i] === to[i]) i++;
  const path = "../".repeat(from.length - i) + to.slice(i).join("/");
  return path.replace(/%/g, "%25").replace(/ /g, "%20").replace(/\(/g, "%28").replace(/\)/g, "%29");
}
// マスに入れるリンクの文字（[ ] は表のリンクを壊すので ( ) に。mandala.py と同じ）
export function cellLink(label, dir, rel) {
  return `[${label.replace(/\[/g, "(").replace(/\]/g, ")").trim()}](${relLink(dir, rel)})`;
}
// マスの文字からリンクを外す（表示名だけを残す）
export function unlinkText(v) {
  return v.replace(new RegExp(LINK_RE.source, "g"), (_, t) => t.replace(/\\(.)/g, "$1"));
}

// ---------------------------------------------------------------- 「副題とそのまわり 8 マス」の単位（ユニット）
// 自分の曼荼羅: 表 p の副題 i。title はその副題、children はそのブロックの 8 マス（真ん中を除く、ブロックの中の位置の順）
const CHILD_POS = [0, 1, 2, 3, 5, 6, 7, 8];          // ブロックの中の位置（4 = 真ん中 = 副題）
export function unitsOf(grids) {
  const out = [];
  grids.forEach((g, p) => {
    for (let i = 0; i < 8; i++) {
      const cells = blockCells(BLOCK_OF_RING[i]);
      out.push({ p, i, title: g[RING[i][0]][RING[i][1]] || g[BLOCK_CENTER[i][0]][BLOCK_CENTER[i][1]], children: CHILD_POS.map((k) => g[cells[k][0]][cells[k][1]]) });
    }
  });
  return out;
}
const filledOf = (u) => u.children.filter((x) => String(x && (x.label ?? x)).trim()).length;
const isEmptyUnit = (u) => !String(u.title || "").trim() && filledOf(u) === 0;

// 並べる（表示だけ）。空のユニットはいつも後ろ（元の順）。order: あいうえお順の添字（呼ぶ側が app_model に聞く）
export function sortUnits(units, key, order) {
  const filled = units.filter((u) => !isEmptyUnit(u)), empty = units.filter(isEmptyUnit);
  const pos = new Map(units.map((u, k) => [u, k]));
  const by = (f) => filled.slice().sort((a, b) => f(a, b) || pos.get(a) - pos.get(b));
  let s = filled;
  if (key === "aiueo" && order) { const rank = new Map(order.map((k, j) => [filled[k], j])); s = by((a, b) => rank.get(a) - rank.get(b)); }
  else if (key === "filled") s = by((a, b) => filledOf(b) - filledOf(a));
  else if (key === "empty") s = by((a, b) => filledOf(a) - filledOf(b));
  else if (key === "new") s = by((a, b) => String(b.time || "").localeCompare(String(a.time || "")));
  else if (key === "old") s = by((a, b) => String(a.time || "").localeCompare(String(b.time || "")));
  return [...s, ...empty];
}

// ユニットの並びから、その順の表を作り直す（「この並びで保存」）。空のユニットだけの表は作らない（最低 1 枚）
export function gridsFromUnits(units, grids, theme) {
  const real = units.filter((u) => !isEmptyUnit(u));
  const pages = Math.max(1, Math.ceil(real.length / 8));
  const out = Array.from({ length: pages }, () => { const g = emptyGrid(); g[THEME[0]][THEME[1]] = theme; return g; });
  real.forEach((u, k) => {
    const g = out[Math.floor(k / 8)], slot = k % 8, src = grids[u.p];
    const sc = blockCells(BLOCK_OF_RING[u.i]), dc = blockCells(BLOCK_OF_RING[slot]);
    for (let j = 0; j < 9; j++) g[dc[j][0]][dc[j][1]] = src[sc[j][0]][sc[j][1]];
    g[RING[slot][0]][RING[slot][1]] = src[RING[u.i][0]][RING[u.i][1]];
  });
  return out;
}

const SORTS_OWN = [["file", "ファイルの順"], ["aiueo", "あいうえお順"], ["filled", "埋まっている順"], ["empty", "空いている順"]];
const SORTS_INDEX = [["file", "索引の順"], ["aiueo", "あいうえお順"], ["filled", "項目の多い順"], ["empty", "項目の少ない順"], ["new", "新しい順"], ["old", "古い順"]];

export function createMandala(ctx, params) {
  const indexMode = !!params.index;
  let rel = params.rel || params.index;
  const el = h("div", "viewbox mdbox keepfocus");
  const bar = h("div", "md-bar");
  const crumbs = h("div", "md-crumbs");
  const state = h("span", "md-state", "");
  const body = h("div", "md-body");
  el.append(bar, body);
  let text = "", hash = "", grids = null, base = null, mode = params.mode || "3", zoom = null, dirty = false, saving = false, timer = null;
  let sortKey = "file", order = null, idx = null, trail = [];
  const copy = (gs) => gs.map((g) => g.map((row) => row.slice()));

  const b3 = button("3×3", () => { mode = "3"; zoom = null; draw(); }, "nav-btn", "各曼荼羅の中心（主題と 8 つの副題）を縦に並べる");
  const b9 = button("9×9", () => { mode = "9"; zoom = null; draw(); }, "nav-btn", "全部のマス");
  const sortSel = h("select", "md-sort");
  sortSel.title = "並び替え（表示だけ。ファイルは変えません）";
  for (const [k, t] of indexMode ? SORTS_INDEX : SORTS_OWN) { const o = h("option", "", t); o.value = k; sortSel.appendChild(o); }
  sortSel.addEventListener("change", async () => { sortKey = sortSel.value; await ensureOrder(); zoom = null; draw(); });
  const saveOrder = button("この並びで保存", () => saveSorted(), "nav-btn", "今の並びのとおりに表を書き直す（副題とそのまわりのマスをまとめて動かす）");
  const openVim = button(indexMode ? "索引を Vim で開く" : "Vim で開く", () => ctx.open(rel), "nav-btn");
  bar.append(crumbs, sortSel, ...(indexMode ? [] : [saveOrder]), b3, b9, openVim, state);

  // ---- 読む ----
  async function load() {
    if (indexMode) {
      const r = await ctx.query("mandala.index", { file: rel });
      if (!r.ok || r.result.missing) { body.textContent = (r.result && r.result.error) || r.error || "読めませんでした"; return; }
      idx = r.result;
      if (idx.error) { body.textContent = idx.error; return; }
      rel = idx.rel;
      order = null; await ensureOrder();
      draw();
      return;
    }
    const r = await ctx.readNote(rel);
    if (!r.ok) { body.textContent = r.error || "読めませんでした"; return; }
    text = r.text; hash = r.hash; grids = parseGrids(text); base = copy(grids); dirty = false;
    if (!/^mandala:\s*true\s*$/m.test(text.split(/\n---\s*\n/)[0] || "")) toast("曼荼羅ノート（mandala: true）ではありません。表の形だけ使います");
    order = null; await ensureOrder();
    draw();
  }
  const themeText = () => (indexMode ? idx.title : (grids[0][THEME[0]][THEME[1]] || "（主題）"));

  // 自分の曼荼羅: 副題が全部埋まったら、下に空の曼荼羅を 1 枚（打ち始めたら保存される）
  function ownUnits() {
    const gs = grids.slice();
    const last = gs[gs.length - 1];
    if (RING.every(([r, c]) => String(last[r][c]).trim())) gs.push(emptyGrid());
    return unitsOf(gs);
  }
  function rawUnits() {
    if (!indexMode) return ownUnits();
    const us = idx.units.map((u) => ({ ...u, title: u.label, children: u.children.slice(0, 8), more: Math.max(0, u.children.length - 8) }));
    // 最後の曼荼羅の空いた枠（索引にノートを足す場所）
    const pad = 8 - (us.length % 8);          // いつも 1 つ以上は空ける（8 の倍数なら下にもう 1 枚）
    for (let k = 0; k < pad; k++) us.push({ empty: true, title: "", children: [] });
    return us;
  }
  async function ensureOrder() {
    if (sortKey !== "aiueo" || order) return;
    const us = rawUnits().filter((u) => !isEmptyUnit(u));
    const texts = us.map((u) => String(u.title || ""));
    const readings = {};
    if (indexMode) for (const u of us) if (u.yomi) readings[u.title] = u.yomi;
    const r = await ctx.query("yomi.order", { texts, readings });
    order = r.ok ? r.result : texts.map((_, k) => k);
  }
  function displayUnits() {
    const us = rawUnits();
    if (sortKey === "file") return us;
    return sortUnits(us, sortKey, order);
  }

  // ---- 書く（自分の曼荼羅だけ） ----
  function setState(t, cls = "") { state.textContent = t; state.className = "md-state " + cls; }
  function schedule() { dirty = true; order = null; setState("未保存", "dirty"); clearTimeout(timer); timer = setTimeout(save, 700); }
  // 表に書く分: 後ろの「主題しか無い」表は書かない（最低 1 枚）
  function gridsToSave() {
    const out = grids.slice();
    while (out.length > 1 && out[out.length - 1].every((row, r) => row.every((v, c) => (r === THEME[0] && c === THEME[1]) || !String(v).trim()))) out.pop();
    return out;
  }
  async function save() {
    if (saving) { schedule(); return; }
    if (!dirty) return;
    saving = true;
    dirty = false;
    let clashes = 0;
    let r = null;
    for (let tries = 0; tries < 3; tries++) {
      const saved = copy(gridsToSave());
      const next = replaceTables(text, saved);
      r = await ctx.commit(rel, next, hash);
      if (r.ok) { text = r.text ?? next; hash = r.hash; base = saved; break; }
      if (!r.conflict) break;
      const disk = await ctx.readNote(rel);
      if (!disk.ok) break;
      const dg = parseGrids(disk.text);
      const m = mergePages(base, grids, dg);
      clashes += m.clashes;
      grids = m.grids; base = dg; text = disk.text; hash = disk.hash;
      refreshValues();
    }
    saving = false;
    if (r && r.ok) setState(clashes ? `保存しました（${clashes} マスはほかでも直されていたので、こちらの文字にしました）` : "保存しました", clashes ? "dirty" : "");
    else { dirty = true; setState((r && r.error) || "保存できませんでした", "err"); }
  }
  function refreshValues() {
    for (const ta of body.querySelectorAll(".md-cell textarea")) {
      const a = ta.closest(".md-cell")._addr;
      if (a && ta !== document.activeElement && ta.value !== valOf(a)) { ta.value = valOf(a); ta.dispatchEvent(new Event("blur")); }
    }
  }
  async function saveSorted() {
    if (indexMode) return;
    if (sortKey === "file") { toast("並び替えを選ぶと、その順で保存できます"); return; }
    const us = displayUnits();
    grids = gridsFromUnits(us, grids.concat([emptyGrid()]), grids[0][THEME[0]][THEME[1]]);
    sortKey = "file"; sortSel.value = "file";
    schedule(); draw();
    toast("この並びで表を書き直しました");
  }

  // 表示のマス → 元の場所 { p, r, c } か { theme: true }
  function valOf(a) {
    if (a.theme) return themeText() === "（主題）" ? "" : themeText();
    const g = grids[a.p];
    return g ? g[a.r][a.c] : "";
  }
  function setCell(a, v) {
    if (a.theme) { for (const g of grids) g[THEME[0]][THEME[1]] = v; schedule(); return; }
    while (grids.length <= a.p) { const g = emptyGrid(); g[THEME[0]][THEME[1]] = grids[0][THEME[0]][THEME[1]]; grids.push(g); }
    const g = grids[a.p];
    const fullBefore = lastFull();
    g[a.r][a.c] = v;
    const m = mirrorOf(a.r, a.c);
    if (m) {
      g[m[0]][m[1]] = v;
      for (const cell of body.querySelectorAll(".md-cell")) {
        const b = cell._addr;
        if (b && !b.theme && b.p === a.p && b.r === m[0] && b.c === m[1]) { const ta = cell.querySelector("textarea"); if (ta && ta !== document.activeElement) { ta.value = v; ta.dispatchEvent(new Event("blur")); } }
      }
    }
    schedule();
    // 最後の曼荼羅の副題が全部埋まった（または空いた）: 下の曼荼羅を出す・消す
    if (fullBefore !== lastFull()) draw();
  }
  const lastFull = () => { const last = grids[grids.length - 1]; return RING.every(([r, c]) => String(last[r][c]).trim()); };
  const dirOf = () => (rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/") + 1) : "");
  async function putNote(a, target, title) {
    if (!title) { const q = await ctx.query("nav.note", { file: target }); title = q.ok && q.result && !q.result.missing ? q.result.title : target.split("/").pop().replace(/\.md$/i, ""); }
    if (target === rel) { toast("この曼荼羅自身は入れられません", "err"); return; }
    const cur = unlinkText(valOf(a)).trim();
    const v = cellLink(cur || title, dirOf(), target);
    setCell(a, v);
    for (const cell of body.querySelectorAll(".md-cell")) if (cell._addr === a) { const ta = cell.querySelector("textarea"); if (ta) { ta.value = v; ta.dispatchEvent(new Event("blur")); } }
    toast(`「${title}」をマスに入れました`);
  }
  const notePicker = (q0, exclude) => ({ key: "file", label: "ノート", type: "picker", placeholder: "題で探す", query: q0,
    load: async (q) => { const res = await ctx.query("nav.notes", { q }); return (res.ok ? res.result : []).filter((x) => x.rel !== exclude).map((x) => ({ value: x.rel, label: x.title, sub: noteSub(x) })); } });
  async function pickNote(a) {
    const cur = unlinkText(valOf(a)).trim();
    const v = await form({
      title: "既存のノートをマスに入れる", ok: "入れる",
      note: cur ? `マスの文字「${cur}」はそのまま表示名にして、選んだノートへのリンクにします。` : "マスには選んだノートの題が入ります（あとから直せます）。",
      fields: [notePicker(cur, rel)],
    });
    if (v && v.file) await putNote(a, v.file);
  }
  function openLink(target) {
    ctx.open(decodeURIComponent((dirOf() + target).split("#")[0]).replace(/[^/]+\/\.\.\//g, ""));
  }
  async function linkCell(a, kind) {
    if (dirty) await save();
    const res = await ctx.op("mandala_link", { file: rel, row: a.r, col: a.c, kind, page: a.p });
    if (!res.ok) { toast(res.error || "作れませんでした", "err"); return; }
    toast(kind === "mandala" ? "曼荼羅を作りました（今日の日記にも載ります）" : "ノートを作りました（今日の日記にも載ります）");
    await load();
  }

  // 索引の曼荼羅: 空いた枠から索引にノートを足す（書くのは Vim: index_add / index_new）
  async function indexAdd(target, name) {
    const r = await ctx.op("index_add", { group: rel, target, name, yomi: "", back: "" });
    if (!r.ok) { toast(r.error || "載せられませんでした", "err"); return; }
    toast(`索引に「${name}」を載せました`);
    setTimeout(load, 500);
  }
  async function indexPick() {
    const v = await form({ title: `索引「${idx.title}」に既存のノートを載せる`, ok: "載せる",
      fields: [{ ...notePicker("", rel), onPick: (it, set) => set("name", it.label) }, { key: "name", label: "索引での名前", required: true }] });
    if (v && v.file) await indexAdd(v.file, v.name.trim());
  }
  async function indexNew() {
    const v = await form({ title: `索引「${idx.title}」に新しいノート`, ok: "作る", fields: [{ key: "name", label: "索引での名前", required: true }] });
    if (!v) return;
    const r = await ctx.op("index_new", { group: rel, name: v.name.trim(), title: "", yomi: "" });
    if (!r.ok) { toast(r.error || "作れませんでした", "err"); return; }
    setTimeout(load, 500);
  }
  function drill(u) {
    if (!u.drill) return;
    trail.push(rel);
    rel = u.drill; zoom = null; sortKey = "file"; sortSel.value = "file";
    load();
  }

  // ---- マス ----
  // spec: { a（元の場所）| null, kind: "theme"|"sub"|"sub2"|"child", unit?, slot? }
  function cellEl(spec, opts = {}) {
    const cls = "md-cell" + (spec.kind === "theme" ? " theme" : spec.kind === "sub" ? " sub" : spec.kind === "sub2" ? " sub2" : "") + (opts.mid ? " mid" : "");
    const cell = h("div", cls);
    if (spec.rc) cell.dataset.rc = spec.rc.join(",");
    if (indexMode) return indexCell(cell, spec, opts);
    const a = spec.a;
    cell._addr = a;
    const ta = h("textarea"); ta.value = valOf(a); ta.rows = 2; ta.spellcheck = false;
    ta.placeholder = spec.kind === "theme" ? "主題" : spec.kind === "sub" ? `副題 ${spec.slot + 1}` : spec.kind === "sub2" ? "（副題）" : "";
    const take = () => { setCell(a, ta.value.replace(/\n/g, " ")); drawTools(); };
    ta.addEventListener("input", (e) => { if (!e.isComposing) take(); });
    ta.addEventListener("compositionend", take);
    ta.addEventListener("keydown", (e) => {
      if (imeActive(e)) return;
      if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); moveFocus(cell, 1); }
      else if (e.key === "Tab") { e.preventDefault(); moveFocus(cell, e.shiftKey ? -1 : 1); }
      else if (e.key === "Escape") { ta.blur(); }
      else if (e.altKey && e.key === "ArrowDown" && opts.zoom) { e.preventDefault(); opts.zoom(); }
      else if (e.altKey && e.key === "ArrowUp" && zoom) { e.preventDefault(); zoom = null; draw(); }
    });
    const disp = h("div", "md-disp");
    disp.addEventListener("mousedown", (e) => { e.preventDefault(); cell.classList.add("editing"); ta.focus(); });
    ta.addEventListener("focus", () => cell.classList.add("editing"));
    ta.addEventListener("blur", () => { cell.classList.remove("editing"); drawDisp(); drawTools(); });
    const isNote = (e) => e.dataTransfer && [...e.dataTransfer.types].includes("text/gnosis-note");
    cell.addEventListener("dragover", (e) => { if (isNote(e)) { e.preventDefault(); e.dataTransfer.dropEffect = "copy"; cell.classList.add("drop"); } });
    cell.addEventListener("dragleave", () => cell.classList.remove("drop"));
    cell.addEventListener("drop", (e) => { cell.classList.remove("drop"); if (!isNote(e)) return; e.preventDefault(); putNote(a, e.dataTransfer.getData("text/gnosis-note")); });
    function drawDisp() {
      const cur = valOf(a);
      disp.textContent = "";
      let last = 0;
      const re = new RegExp(LINK_RE.source, "g");
      let m;
      while ((m = re.exec(cur))) {
        if (m.index > last) disp.appendChild(document.createTextNode(cur.slice(last, m.index)));
        disp.appendChild(h("span", "md-linktext", m[1].replace(/\\(.)/g, "$1")));
        last = m.index + m[0].length;
      }
      if (last < cur.length) disp.appendChild(document.createTextNode(cur.slice(last)));
    }
    drawDisp();
    cell.append(disp, ta);
    const tools = h("div", "md-tools");
    let toolsKey = null;
    function drawTools() {
      const cur = valOf(a);
      const lk = LINK_RE.exec(cur);
      const key = lk ? "L" + lk[2] : cur.trim() ? "T" : "";
      if (key === toolsKey) return;
      toolsKey = key;
      tools.textContent = "";
      cell.classList.toggle("linked", !!lk);
      if (spec.kind !== "theme") {
        if (lk) {
          tools.appendChild(button("開く", () => openLink(lk[2]), "md-tool", "リンク先を Vim で開く"));
          tools.appendChild(button("外す", () => { const v = unlinkText(valOf(a)); ta.value = v; setCell(a, v); drawDisp(); drawTools(); }, "md-tool", "リンクを外して文字だけ残す"));
        } else if (cur.trim()) {
          tools.appendChild(button("ノートに", () => linkCell(a, "note"), "md-tool", "このマスの文字で新しいノートを作り、マスをリンクにする"));
          tools.appendChild(button("既存…", () => pickNote(a), "md-tool", "既存のノートを選んで、このマスをそのノートへのリンクにする（ノートをマスへドラッグしても入ります）"));
          tools.appendChild(button("曼荼羅に", () => linkCell(a, "mandala"), "md-tool", "このマスの文字を主題にした別の曼荼羅を作る"));
        } else {
          tools.appendChild(button("既存のノート…", () => pickNote(a), "md-tool", "既存のノートを選んでこのマスに入れる（ノートをマスへドラッグしても入ります）"));
        }
      }
      if (opts.zoom) tools.appendChild(button("広げる ▸", opts.zoom, "md-tool zoom", "このマスを中心に 8 マスで広げる（Alt+↓）"));
    }
    drawTools();
    cell.appendChild(tools);
    return cell;
  }

  // 索引の曼荼羅のマス（読むだけ。押すと開く）
  function indexCell(cell, spec, opts) {
    const u = spec.unit;
    const tools = h("div", "md-tools");
    const disp = h("div", "md-disp show");
    let item = null;
    if (spec.kind === "theme") { item = { label: idx.title, rel: idx.rel }; }
    else if (spec.kind === "sub" || spec.kind === "sub2") item = u && !u.empty ? { label: u.label, rel: u.rel } : null;
    else if (u && !u.empty) item = u.children[spec.child] || null;
    if (item) {
      const t = h("span", "md-linktext", item.label);
      disp.appendChild(t);
      cell.classList.add("linked");
      disp.addEventListener("click", () => ctx.open(item.rel));
      cell.title = item.title && item.title !== item.label ? `${item.label}（${item.title}）` : item.label;
      if (item.rel) { cell.draggable = true; cell.addEventListener("dragstart", (e) => { e.dataTransfer.setData("text/gnosis-note", item.rel); e.dataTransfer.effectAllowed = "copy"; }); }
    }
    if ((spec.kind === "sub" || spec.kind === "sub2") && u) {
      if (u.empty && spec.kind === "sub") {
        tools.append(button("＋ 新しいノート", () => indexNew(), "md-tool", "この索引に新しいノートを作って載せる"), button("＋ 既存", () => indexPick(), "md-tool", "この索引に既存のノートを載せる（ノートをここへドラッグしても載ります）"));
        const isNote = (e) => e.dataTransfer && [...e.dataTransfer.types].includes("text/gnosis-note");
        cell.addEventListener("dragover", (e) => { if (isNote(e)) { e.preventDefault(); cell.classList.add("drop"); } });
        cell.addEventListener("dragleave", () => cell.classList.remove("drop"));
        cell.addEventListener("drop", async (e) => {
          cell.classList.remove("drop"); if (!isNote(e)) return; e.preventDefault();
          const target = e.dataTransfer.getData("text/gnosis-note");
          const q = await ctx.query("nav.note", { file: target });
          await indexAdd(target, q.ok && q.result && q.result.title ? q.result.title : target);
        });
      }
      if (!u.empty && u.drill && spec.kind === "sub") tools.appendChild(button("この索引へ ▸▸", () => drill(u), "md-tool", "この項目のトピック索引を真ん中にして入る"));
      if (!u.empty && u.more && spec.kind === "sub2") disp.appendChild(h("span", "md-more", ` ほか ${u.more}`));
    }
    if (opts.zoom) tools.appendChild(button("広げる ▸", opts.zoom, "md-tool zoom", "この項目のまわりを 3×3 で"));
    cell.append(disp, tools);
    return cell;
  }

  function moveFocus(cell, k) {
    const all = [...body.querySelectorAll(".md-cell textarea")];
    const i = all.indexOf(cell.querySelector("textarea"));
    const n = all[(i + k + all.length) % all.length];
    if (n) n.focus();
  }

  // 表示の d 枚目の (r, c) のマスの中身
  function specOf(units, d, r, c) { return { ...specAt(units, d, r, c), rc: [r, c] }; }
  function specAt(units, d, r, c) {
    if (r === THEME[0] && c === THEME[1]) return { kind: "theme", a: { theme: true } };
    const ringK = RING.findIndex(([a, b]) => a === r && b === c);
    const centerK = BLOCK_CENTER.findIndex(([a, b]) => a === r && b === c);
    const blk = Math.floor(r / 3) * 3 + Math.floor(c / 3);
    const k = ringK >= 0 ? ringK : centerK >= 0 ? centerK : BLOCK_OF_RING.indexOf(blk);
    const u = units[d * 8 + k];
    if (!u) return { kind: "child", a: null };
    if (ringK >= 0 || centerK >= 0) {
      return { kind: ringK >= 0 ? "sub" : "sub2", unit: u, slot: k, a: indexMode ? null : { p: u.p, r: (ringK >= 0 ? RING : BLOCK_CENTER)[u.i][0], c: (ringK >= 0 ? RING : BLOCK_CENTER)[u.i][1] } };
    }
    const pos = blockCells(blk).findIndex(([a, bb]) => a === r && bb === c);
    const child = CHILD_POS.indexOf(pos);
    if (indexMode) return { kind: "child", unit: u, child };
    const sc = blockCells(BLOCK_OF_RING[u.i])[pos];
    return { kind: "child", unit: u, child, a: { p: u.p, r: sc[0], c: sc[1] } };
  }

  function draw() {
    if (indexMode ? !idx : !grids) return;
    b3.setAttribute("aria-pressed", String(mode === "3"));
    b9.setAttribute("aria-pressed", String(mode === "9"));
    saveOrder.hidden = sortKey === "file";
    const scroll = body.scrollTop;
    // 打っている最中のマスは、描き直したあとも同じマスで続けられるように
    const act = document.activeElement && body.contains(document.activeElement) && document.activeElement.closest(".md-cell");
    const keep = act && act._addr ? { a: act._addr, s: document.activeElement.selectionStart, e: document.activeElement.selectionEnd } : null;
    if (keep) setTimeout(() => {
      for (const c of body.querySelectorAll(".md-cell")) {
        const b = c._addr;
        if (b && (b === keep.a || (!b.theme && !keep.a.theme && b.p === keep.a.p && b.r === keep.a.r && b.c === keep.a.c))) { const ta = c.querySelector("textarea"); if (ta) { ta.focus(); ta.setSelectionRange(keep.s, keep.e); } break; }
      }
    }, 0);
    body.textContent = "";
    crumbs.textContent = "";
    const theme = themeText();
    if (indexMode && trail.length) {
      crumbs.appendChild(button("‹ 戻る", () => { rel = trail.pop(); zoom = null; load(); }, "md-crumb", "前の索引へ"));
      crumbs.appendChild(h("span", "nav-sep", "|"));
    }
    if (indexMode && idx.path) crumbs.appendChild(h("span", "md-path", idx.path.replace(/ › [^›]*$/, "") + " ›"));
    crumbs.appendChild(button(theme, () => { zoom = null; draw(); }, "md-crumb"));
    const units = displayUnits();
    const pages = Math.max(1, Math.ceil(units.length / 8));
    // 3×3 でブロックへ入っている
    if (zoom) {
      const u = units[zoom.k];
      crumbs.appendChild(h("span", "nav-sep", "›"));
      crumbs.appendChild(h("span", "md-crumb cur", (u && unlinkText(String(u.title || ""))) || `副題 ${zoom.k % 8 + 1}`));
      const d = Math.floor(zoom.k / 8), slot = zoom.k % 8;
      const g = h("div", "md-grid3");
      blockCells(BLOCK_OF_RING[slot]).forEach(([r, c], j) => g.appendChild(cellEl(specOf(units, d, r, c), { mid: j === 4 })));
      body.appendChild(g);
      body.appendChild(h("div", "nav-dim small md-help", "Alt+↑ か上の主題で戻る。"));
      setTimeout(() => body.querySelector(".md-cell:not(.mid) textarea")?.focus(), 0);
      return;
    }
    for (let d = 0; d < pages; d++) {
      const page = h("section", "md-page");
      const head = h("div", "md-pagehead");
      const pu = units.slice(d * 8, d * 8 + 8);
      const filled = pu.filter((u) => !isEmptyUnit(u)).length;
      head.append(h("span", "md-pagetitle", theme), h("span", "md-pagenum", pages > 1 ? `${d + 1} / ${pages}` : ""), h("span", "md-pagecount", `副題 ${filled}/8`));
      page.appendChild(head);
      if (mode === "9") {
        const g = h("div", "md-grid9");
        for (let b = 0; b < 9; b++) {
          const blk = h("div", "md-block" + (b === 4 ? " center" : ""));
          for (const [r, c] of blockCells(b)) blk.appendChild(cellEl(specOf(units, d, r, c)));
          g.appendChild(blk);
        }
        page.appendChild(g);
      } else {
        const g = h("div", "md-grid3");
        blockCells(4).forEach(([r, c], j) => {
          const spec = specOf(units, d, r, c);
          const opts = { mid: j === 4 };
          if (spec.kind === "sub" && !(indexMode && (!spec.unit || spec.unit.empty))) { const k = d * 8 + spec.slot; opts.zoom = () => { zoom = { k }; draw(); }; }
          g.appendChild(cellEl(spec, opts));
        });
        page.appendChild(g);
      }
      body.appendChild(page);
    }
    const help = indexMode
      ? "項目を押すとそのノートを Vim で開く。「この索引へ ▸▸」でトピック索引を真ん中にして入る。空いた枠から索引にノートを足せる（ノートのドラッグでも）。項目が 8 つを超えると、下に同じ索引の曼荼羅が続く。"
      : "Enter/Tab で次のマス。副題の「広げる ▸」（Alt+↓）でそのブロックへ。8 つの副題が埋まると、下に同じ主題の曼荼羅が続く。既存のノートは「既存…」か、左右のバーからマスへドラッグ。打ち終わって少しすると Vim が保存します。";
    body.appendChild(h("div", "nav-dim small md-help", help));
    body.scrollTop = scroll;
  }

  load();
  return { el, loaded: true, onShow: () => { if (!dirty) load(); } };
}
