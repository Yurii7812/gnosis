// ローカルグラフ: 今のノートを中心に、つながるノートを円状に並べて描く（Obsidian の局所グラフ相当）。
// neighbors(rel) → [rel] を受け取り、深さ 1〜2 のノードと辺だけを描く。
const SVG_NS = "http://www.w3.org/2000/svg";

export function buildLocal(center, depth, neighbors) {
  const nodes = new Map([[center, { rel: center, depth: 0 }]]);
  const ring1 = (neighbors(center) || []).filter((r) => r !== center);
  for (const r of ring1) if (!nodes.has(r)) nodes.set(r, { rel: r, depth: 1 });
  if (depth >= 2) {
    for (const r of ring1) {
      for (const r2 of neighbors(r) || []) {
        if (r2 === center || nodes.has(r2)) continue;
        nodes.set(r2, { rel: r2, depth: 2, via: r });
      }
    }
  }
  // 辺: 描いているノート同士のつながり（重複なし）
  const edges = [];
  const seen = new Set();
  for (const a of nodes.keys()) {
    for (const b of neighbors(a) || []) {
      if (!nodes.has(b) || a === b) continue;
      const k = a < b ? a + "|" + b : b + "|" + a;
      if (seen.has(k)) continue;
      seen.add(k);
      edges.push([a, b]);
    }
  }
  return { nodes: [...nodes.values()], edges };
}

// 円状レイアウト。深さ 1 は内側の円、深さ 2 は外側の円（親になるノートの角度の近くに置く）。
export function layout(model, width, height) {
  const cx = width / 2, cy = height / 2;
  const pos = new Map();
  pos.set(model.nodes.find((n) => n.depth === 0).rel, { x: cx, y: cy });
  const r1 = Math.min(width, height) * 0.30;
  const r2 = Math.min(width, height) * 0.46;
  const ones = model.nodes.filter((n) => n.depth === 1);
  ones.forEach((n, i) => {
    const a = (2 * Math.PI * i) / Math.max(1, ones.length) - Math.PI / 2;
    pos.set(n.rel, { x: cx + r1 * Math.cos(a), y: cy + r1 * Math.sin(a), a });
  });
  const twos = model.nodes.filter((n) => n.depth === 2);
  const byVia = new Map();
  for (const n of twos) {
    if (!byVia.has(n.via)) byVia.set(n.via, []);
    byVia.get(n.via).push(n);
  }
  for (const [via, group] of byVia) {
    const base = pos.get(via)?.a ?? 0;
    const spread = Math.min(0.5, 0.18 * group.length);
    group.forEach((n, i) => {
      const off = group.length === 1 ? 0 : (i / (group.length - 1) - 0.5) * 2 * spread;
      const a = base + off;
      pos.set(n.rel, { x: cx + r2 * Math.cos(a), y: cy + r2 * Math.sin(a) });
    });
  }
  return pos;
}

function el(name, attrs = {}) {
  const e = document.createElementNS(SVG_NS, name);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, String(v));
  return e;
}

// svg 要素を描き直す。label(rel) → 表示名、onOpen(rel) → クリック時、current は中心のノート。
export function drawLocal(svg, model, { width, height, label, onOpen }) {
  svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
  svg.innerHTML = "";
  const pos = layout(model, width, height);
  const gEdges = el("g", { class: "lg-edges" });
  for (const [a, b] of model.edges) {
    const pa = pos.get(a), pb = pos.get(b);
    if (!pa || !pb) continue;
    gEdges.appendChild(el("line", { x1: pa.x, y1: pa.y, x2: pb.x, y2: pb.y, class: "lg-edge" }));
  }
  svg.appendChild(gEdges);
  const gNodes = el("g", { class: "lg-nodes" });
  for (const n of model.nodes) {
    const p = pos.get(n.rel);
    if (!p) continue;
    const g = el("g", { class: `lg-node d${n.depth}`, transform: `translate(${p.x},${p.y})` });
    const r = n.depth === 0 ? 7 : n.depth === 1 ? 5.5 : 4;
    g.appendChild(el("circle", { r }));
    const t = el("text", { x: 0, y: -r - 4, "text-anchor": "middle", class: "lg-label" });
    const name = label(n.rel);
    t.textContent = name.length > 14 ? name.slice(0, 13) + "…" : name;
    g.appendChild(t);
    g.addEventListener("click", () => onOpen(n.rel));
    const title = el("title");
    title.textContent = name;
    g.appendChild(title);
    gNodes.appendChild(g);
  }
  svg.appendChild(gNodes);
}
