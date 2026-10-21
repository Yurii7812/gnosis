// `\A` のタブ・分割ペインのレイアウト（DOM に触れない純関数。すべて新しい木を返し、元は変えない）。
//   木の節: { type: "tabs", id, tabs: [{id, kind, title, params, pinned}], active: タブ id }   … 1 つのペイン（タブの束）
//           { type: "split", id, dir: "row"|"col", ratio: 0..1, a: 節, b: 節 }                   … 2 つに分ける（row = 左右、col = 上下）
//   種類 kind: "vim"（ちょうど 1 つ。本物の Vim。閉じられない）と、表示専用ビュー（cards / table / timeline / graph / fznav / search / note …）。
//   保存・復元（serialize / restore）では、壊れた入力でも必ず「Vim タブが 1 つある」正しい木に直す。
let seq = 0;
const nid = (p) => `${p}${++seq}`;

export function newTab(kind, { title = "", params = {}, pinned = false } = {}) {
  return { id: nid("t"), kind, title: title || kind, params, pinned };
}
export function newLayout() {
  const vim = newTab("vim", { title: "Vim" });
  return { type: "tabs", id: nid("p"), tabs: [vim], active: vim.id };
}

// ---- 検索 ----
export function walk(node, fn) {
  fn(node);
  if (node.type === "split") { walk(node.a, fn); walk(node.b, fn); }
}
export function panes(layout) { const out = []; walk(layout, (n) => { if (n.type === "tabs") out.push(n); }); return out; }
export function findTab(layout, tabId) {
  for (const p of panes(layout)) { const i = p.tabs.findIndex((t) => t.id === tabId); if (i >= 0) return { pane: p, index: i, tab: p.tabs[i] }; }
  return null;
}
export function findPane(layout, paneId) { return panes(layout).find((p) => p.id === paneId) || null; }
export function vimTab(layout) { for (const p of panes(layout)) { const t = p.tabs.find((x) => x.kind === "vim"); if (t) return t; } return null; }

// 木の一部を置き換える（id の節を f(節) の結果に）。null を返すとその節を消して、兄弟で置き換える。
function mapNode(node, id, f) {
  if (node.id === id) return f(node);
  if (node.type !== "split") return node;
  const a = mapNode(node.a, id, f), b = mapNode(node.b, id, f);
  if (a === null) return b;
  if (b === null) return a;
  return a === node.a && b === node.b ? node : { ...node, a, b };
}

// ---- タブ ----
// 同じ種類・同じ引数のタブがそのペインにあれば、それを前に出す（重ねて開かない）
export function openTab(layout, paneId, tab) {
  const pane = findPane(layout, paneId) || panes(layout)[0];
  const same = pane.tabs.find((t) => t.kind === tab.kind && JSON.stringify(t.params) === JSON.stringify(tab.params) && tab.kind !== "vim");
  if (same) return mapNode(layout, pane.id, (n) => ({ ...n, active: same.id }));
  return mapNode(layout, pane.id, (n) => ({ ...n, tabs: [...n.tabs, tab], active: tab.id }));
}
export function activateTab(layout, tabId) {
  const f = findTab(layout, tabId);
  return f ? mapNode(layout, f.pane.id, (n) => ({ ...n, active: tabId })) : layout;
}

// 閉じる。Vim タブは閉じられない。固定（pinned）は force のときだけ。{layout, closed}（閉じられなければ closed は null）
export function closeTab(layout, tabId, { force = false } = {}) {
  const f = findTab(layout, tabId);
  if (!f || f.tab.kind === "vim" || (f.tab.pinned && !force)) return { layout, closed: null };
  const rest = f.pane.tabs.filter((t) => t.id !== tabId);
  const closed = { tab: f.tab, index: f.index, paneId: f.pane.id };
  if (rest.length === 0) return { layout: mapNode(layout, f.pane.id, () => null), closed };         // ペインごと畳む（兄弟が広がる）
  const active = f.pane.active === tabId ? rest[Math.min(f.index, rest.length - 1)].id : f.pane.active;
  return { layout: mapNode(layout, f.pane.id, (n) => ({ ...n, tabs: rest, active })), closed };
}
export function setPinned(layout, tabId, pinned) {
  const f = findTab(layout, tabId);
  if (!f) return layout;
  return mapNode(layout, f.pane.id, (n) => ({ ...n, tabs: n.tabs.map((t) => (t.id === tabId ? { ...t, pinned: !!pinned } : t)) }));
}
// 並べ替え・別のペインへの移動（index を省くと末尾）。固定のタブは先頭側にまとまる。
export function moveTab(layout, tabId, toPaneId, index) {
  const f = findTab(layout, tabId);
  const dest = findPane(layout, toPaneId);
  if (!f || !dest) return layout;
  if (f.pane.id === dest.id) {
    const tabs = f.pane.tabs.filter((t) => t.id !== tabId);
    const i = index == null ? tabs.length : Math.max(0, Math.min(index, tabs.length));
    tabs.splice(i, 0, f.tab);
    return mapNode(layout, dest.id, (n) => ({ ...n, tabs: pinFirst(tabs) }));
  }
  const removed = closeTab(layout, tabId, { force: true });
  if (!removed.closed && f.tab.kind === "vim") {                    // Vim タブは移せる（閉じられないだけ）。元のペインから外して移す
    const rest = f.pane.tabs.filter((t) => t.id !== tabId);
    let lay = rest.length ? mapNode(layout, f.pane.id, (n) => ({ ...n, tabs: rest, active: n.active === tabId ? rest[0].id : n.active })) : mapNode(layout, f.pane.id, () => null);
    const d = findPane(lay, toPaneId);
    const tabs = [...d.tabs]; tabs.splice(index == null ? tabs.length : index, 0, f.tab);
    return mapNode(lay, d.id, (n) => ({ ...n, tabs: pinFirst(tabs), active: tabId }));
  }
  const d = findPane(removed.layout, toPaneId);
  if (!d) return layout;                                            // 移動先が畳まれて無くなった（同じペイン）
  const tabs = [...d.tabs];
  tabs.splice(index == null ? tabs.length : Math.max(0, Math.min(index, tabs.length)), 0, f.tab);
  return mapNode(removed.layout, d.id, (n) => ({ ...n, tabs: pinFirst(tabs), active: tabId }));
}
function pinFirst(tabs) { return [...tabs.filter((t) => t.pinned), ...tabs.filter((t) => !t.pinned)]; }

// ---- 分割 ----
// ペインを 2 つに分ける。tab を渡すとそれを新しい側に置く（無ければ、今のタブを複製できない種類は空のまま作らない: tab 必須）。
// side: "after"（右／下）または "before"（左／上）。
export function splitPane(layout, paneId, dir, tab, side = "after") {
  const pane = findPane(layout, paneId);
  if (!pane || !tab) return layout;
  const fresh = { type: "tabs", id: nid("p"), tabs: [tab], active: tab.id };
  return mapNode(layout, pane.id, (n) => ({ type: "split", id: nid("s"), dir, ratio: 0.5, a: side === "before" ? fresh : n, b: side === "before" ? n : fresh }));
}
// 既存のタブを新しいペインへ移して分割する（ドラッグ配置）。元のペインが空になれば畳む。
export function splitWithTab(layout, paneId, dir, tabId, side = "after") {
  const f = findTab(layout, tabId);
  if (!f) return layout;
  if (f.pane.id === paneId && f.pane.tabs.length === 1) return layout;      // 1 つしかないタブを自分自身と分けても意味がない
  let lay = layout;
  if (f.tab.kind === "vim") {
    const rest = f.pane.tabs.filter((t) => t.id !== tabId);
    lay = rest.length ? mapNode(lay, f.pane.id, (n) => ({ ...n, tabs: rest, active: n.active === tabId ? rest[0].id : n.active })) : mapNode(lay, f.pane.id, () => null);
  } else {
    lay = closeTab(lay, tabId, { force: true }).layout;
  }
  const target = findPane(lay, paneId) || panes(lay)[0];
  return splitPane(lay, target.id, dir, f.tab, side);
}
export function setRatio(layout, splitId, ratio) {
  const r = Math.max(0.1, Math.min(0.9, Number(ratio) || 0.5));
  return mapNode(layout, splitId, (n) => (n.type === "split" ? { ...n, ratio: r } : n));
}
// 分割を解除: 指定のペインの全タブを兄弟側（隣）のペインへ移して、このペインを畳む。Vim タブが含まれるときは Vim 側へ。
export function unsplit(layout, paneId) {
  const p = findPane(layout, paneId);
  if (!p || p.id === layout.id) return layout;
  const all = panes(layout);
  const other = all.find((x) => x.id !== paneId);
  if (!other) return layout;
  const moved = p.tabs;
  let lay = mapNode(layout, p.id, () => null);
  const sib = panes(lay).find((x) => x.id === other.id) || panes(lay)[0];
  return mapNode(lay, sib.id, (n) => ({ ...n, tabs: pinFirst([...n.tabs, ...moved.filter((t) => !n.tabs.some((u) => u.kind === t.kind && u.kind !== "vim" && JSON.stringify(u.params) === JSON.stringify(t.params)))]), active: n.active }));
}

// ---- 閉じたタブの再開 ----
export function createClosedStack(limit = 20) {
  const st = [];
  return {
    push(c) { if (c && c.tab && c.tab.kind !== "vim") { st.push(c); if (st.length > limit) st.shift(); } },
    pop() { return st.pop() || null; },
    size: () => st.length,
    toJSON: () => st.map((c) => ({ tab: c.tab })),
    load(list) { st.length = 0; for (const c of Array.isArray(list) ? list : []) if (c && c.tab && typeof c.tab.kind === "string") st.push({ tab: c.tab }); },
  };
}
// 閉じたタブを、指定のペイン（無ければ最初のペイン）へ開き直す
export function reopen(layout, closed, paneId) {
  if (!closed) return layout;
  const tab = { ...closed.tab, id: nid("t") };
  return openTab(layout, paneId || panes(layout)[0].id, tab);
}

// ---- 保存・復元 ----
export function serialize(layout) { return JSON.stringify(layout); }
const KINDS = new Set(["vim", "index", "analysis", "cards", "table", "timeline", "graph", "fznav", "search", "note", "v2"]);
export function restore(text) {
  let raw;
  try { raw = typeof text === "string" ? JSON.parse(text) : text; } catch { return newLayout(); }
  const fix = (n) => {
    if (!n || typeof n !== "object") return null;
    if (n.type === "tabs") {
      const tabs = (Array.isArray(n.tabs) ? n.tabs : []).filter((t) => t && typeof t.kind === "string" && KINDS.has(t.kind))
        .map((t) => ({ id: typeof t.id === "string" ? t.id : nid("t"), kind: t.kind, title: String(t.title || t.kind), params: t.params && typeof t.params === "object" ? t.params : {}, pinned: !!t.pinned }));
      if (!tabs.length) return null;
      return { type: "tabs", id: typeof n.id === "string" ? n.id : nid("p"), tabs, active: tabs.some((t) => t.id === n.active) ? n.active : tabs[0].id };
    }
    if (n.type === "split") {
      const a = fix(n.a), b = fix(n.b);
      if (!a) return b; if (!b) return a;
      return { type: "split", id: typeof n.id === "string" ? n.id : nid("s"), dir: n.dir === "col" ? "col" : "row", ratio: Math.max(0.1, Math.min(0.9, Number(n.ratio) || 0.5)), a, b };
    }
    return null;
  };
  let lay = fix(raw);
  if (!lay) return newLayout();
  // Vim タブは必ず 1 つ（無ければ最初のペインに足す。2 つ以上あれば最初の 1 つだけ残す）
  let seen = false;
  const dedup = (n) => {
    if (n.type === "split") return { ...n, a: dedup(n.a), b: dedup(n.b) };
    const tabs = n.tabs.filter((t) => { if (t.kind !== "vim") return true; if (seen) return false; seen = true; return true; });
    return { ...n, tabs, active: tabs.some((t) => t.id === n.active) ? n.active : (tabs[0] ? tabs[0].id : "") };
  };
  lay = dedup(lay);
  // 空になったペインを畳む
  const prune = (n) => { if (n.type === "split") { const a = prune(n.a), b = prune(n.b); if (!a) return b; if (!b) return a; return { ...n, a, b }; } return n.tabs.length ? n : null; };
  lay = prune(lay) || newLayout();
  if (!vimTab(lay)) { const first = panes(lay)[0]; lay = mapNode(lay, first.id, (n) => { const v = newTab("vim", { title: "Vim" }); return { ...n, tabs: [v, ...n.tabs], active: v.id }; }); }
  // 採番を、復元した id より大きくする（重ならないように）
  walk(lay, (n) => { const m = /^[tps](\d+)$/.exec(n.id || ""); if (m) seq = Math.max(seq, Number(m[1])); if (n.type === "tabs") for (const t of n.tabs) { const k = /^t(\d+)$/.exec(t.id); if (k) seq = Math.max(seq, Number(k[1])); } });
  return lay;
}
