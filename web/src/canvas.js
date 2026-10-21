// キャンバス（タブ）。ノートのカード・文字のカード・矢印（名前つき）を自由に並べる。
// 保存はふつうの Markdown ノート（front matter `canvas: true`）:
//   # 題
//   （自由な本文）
//   [カードのノート](x.md)      ← 置いたノートへのリンクの行（Markdown ビューアでも辿れる。この画面が書き直す）
//   ```gnosis-canvas
//   {"nodes": [...], "edges": [...]}   ← 位置・大きさ・矢印（この画面が書き直す）
//   ```
// この画面が書き換えるのは、上の 2 つ（コードブロックと、その直前に続くリンクだけの行）だけ。ほかの本文は残す。
// 保存は Vim（:write）。読んだときと内容が違えば上書きせず読み直す。
import { h, button, form, toast, noteSub } from "./ui.js";

const FENCE = "```gnosis-canvas";
const COLORS = ["", "#d4a72c", "#57ab5a", "#539bf5", "#e5534b", "#b083f0", "#768390"];
const LINK_LINE_RE = /^\s*\[(?:\\.|[^\]\\])*\]\([^)\s]+\)\s*$/;

export function parseCanvas(text) {
  const lines = text.split("\n");
  const a = lines.findIndex((l) => l.trim() === FENCE);
  if (a < 0) return { nodes: [], edges: [] };
  let b = a + 1;
  while (b < lines.length && lines[b].trim() !== "```") b++;
  try {
    const o = JSON.parse(lines.slice(a + 1, b).join("\n") || "{}");
    return { nodes: Array.isArray(o.nodes) ? o.nodes : [], edges: Array.isArray(o.edges) ? o.edges : [] };
  } catch { return { nodes: [], edges: [], broken: true }; }
}

const relFrom = (dir, file) => {
  const a = dir ? dir.split("/") : [];
  const b = file.split("/");
  let i = 0;
  while (i < a.length && i < b.length - 1 && a[i] === b[i]) i++;
  return "../".repeat(a.length - i) + b.slice(i).join("/");
};

export function writeCanvas(text, data, titles, canvasRel) {
  const lines = text.split("\n");
  const dir = canvasRel.includes("/") ? canvasRel.slice(0, canvasRel.lastIndexOf("/")) : "";
  const esc = (s) => String(s).replace(/([\\[\]])/g, "\\$1");
  const files = [...new Set(data.nodes.filter((n) => n.type === "note" && n.file).map((n) => n.file))];
  const links = files.map((f) => `[${esc(titles[f] || f.split("/").pop().replace(/\.md$/, ""))}](${encodeURI(relFrom(dir, f))})`);
  const json = JSON.stringify({ nodes: data.nodes, edges: data.edges });
  let a = lines.findIndex((l) => l.trim() === FENCE);
  if (a < 0) {
    let at = lines.length;
    while (at > 0 && !lines[at - 1].trim()) at--;
    const add = (at > 0 ? [""] : []).concat(links, [FENCE, json, "```"]);
    lines.splice(at, lines.length - at, ...add);
    return lines.join("\n") + "\n";
  }
  let b = a + 1;
  while (b < lines.length && lines[b].trim() !== "```") b++;
  let s = a;
  while (s > 0 && LINK_LINE_RE.test(lines[s - 1])) s--;
  lines.splice(s, Math.min(b, lines.length - 1) - s + 1, ...links, FENCE, json, "```");
  return lines.join("\n");
}

let seq = 0;
const newId = (p) => p + Date.now().toString(36) + (seq++).toString(36);

export function createCanvas(ctx, params) {
  const rel = params.rel;
  const el = h("div", "viewbox cvbox keepfocus");
  el.tabIndex = 0;
  const bar = h("div", "cv-bar");
  const state = h("span", "md-state", "");
  const stage = h("div", "cv-stage");
  const world = h("div", "cv-world");
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg"); svg.classList.add("cv-edges");
  world.appendChild(svg);
  stage.appendChild(world);
  el.append(bar, stage);
  let text = "", hash = "", data = { nodes: [], edges: [] }, titles = {}, previews = {};
  let view = { x: 40, y: 40, k: 1 };
  let selected = new Set(), selEdge = null, dirty = false, saving = false, timer = null, linking = null;

  bar.append(
    button("＋ ノート", () => addNote(), "nav-btn primary", "ノートをカードとして置く"),
    button("＋ 文字", () => addText(), "nav-btn", "文字のカード（空いた所をダブルクリックでも）"),
    button("全体を表示", () => fit(), "nav-btn", "全部のカードが見えるように（f）"),
    button("−", () => zoom(1 / 1.2), "nav-btn"), button("＋", () => zoom(1.2), "nav-btn"),
    h("span", "cv-hint", "ドラッグで移動・右端の ● から引いて矢印・ダブルクリックで開く/直す・Delete で消す"),
    button("Vim で開く", () => ctx.open(rel), "nav-btn"), state);

  async function load() {
    const r = await ctx.readNote(rel);
    if (!r.ok) { stage.textContent = r.error || "読めませんでした"; return; }
    text = r.text; hash = r.hash; data = parseCanvas(text); dirty = false;
    if (data.broken) toast("キャンバスのデータが壊れています。保存すると空から書き直します", "err");
    await fetchTitles(data.nodes.filter((n) => n.type === "note").map((n) => n.file));
    draw();
  }
  async function fetchTitles(files) {
    for (const f of files) {
      if (titles[f] !== undefined) continue;
      const r = await ctx.query("nav.note", { file: f });
      titles[f] = r.ok && !r.result.missing ? r.result.title : f;
      previews[f] = r.ok ? (r.result.preview || "") : "";
      if (r.ok && r.result.missing) previews[f] = "（ノートが見つかりません）";
    }
  }
  function setState(t, cls = "") { state.textContent = t; state.className = "md-state " + cls; }
  function schedule() { dirty = true; setState("未保存", "dirty"); clearTimeout(timer); timer = setTimeout(save, 700); }
  async function save() {
    if (saving) { schedule(); return; }
    if (!dirty) return;
    saving = true;
    dirty = false;
    let r = null;
    // 保存のあとの自動同期や Vim が本文を書き換えていることがある。キャンバスの部分（カードと矢印）はこちらの版、ほかの本文はファイルの版で保存し直す
    for (let tries = 0; tries < 3; tries++) {
      const next = writeCanvas(text, data, titles, rel);
      r = await ctx.commit(rel, next, hash);
      if (r.ok) { text = r.text ?? next; hash = r.hash; break; }
      if (!r.conflict) break;
      const disk = await ctx.readNote(rel);
      if (!disk.ok) break;
      text = disk.text; hash = disk.hash;
    }
    saving = false;
    if (r && r.ok) setState("保存しました");
    else { dirty = true; setState((r && r.error) || "保存できませんでした", "err"); }
  }

  // ---- 表示 ----
  function applyView() { world.style.transform = `translate(${view.x}px, ${view.y}px) scale(${view.k})`; }
  function zoom(f, cx, cy) {
    const r = stage.getBoundingClientRect();
    cx = cx ?? r.width / 2; cy = cy ?? r.height / 2;
    const k = Math.min(3, Math.max(0.2, view.k * f));
    view.x = cx - (cx - view.x) * (k / view.k); view.y = cy - (cy - view.y) * (k / view.k); view.k = k;
    applyView();
  }
  function fit() {
    if (!data.nodes.length) { view = { x: 40, y: 40, k: 1 }; applyView(); return; }
    const r = stage.getBoundingClientRect();
    const x0 = Math.min(...data.nodes.map((n) => n.x)), y0 = Math.min(...data.nodes.map((n) => n.y));
    const x1 = Math.max(...data.nodes.map((n) => n.x + n.w)), y1 = Math.max(...data.nodes.map((n) => n.y + n.h));
    const k = Math.min(1.5, Math.max(0.2, Math.min((r.width - 60) / (x1 - x0 || 1), (r.height - 60) / (y1 - y0 || 1))));
    view = { k, x: (r.width - (x1 - x0) * k) / 2 - x0 * k, y: (r.height - (y1 - y0) * k) / 2 - y0 * k };
    applyView();
  }
  const toWorld = (cx, cy) => { const r = stage.getBoundingClientRect(); return { x: (cx - r.left - view.x) / view.k, y: (cy - r.top - view.y) / view.k }; };
  const center = () => { const r = stage.getBoundingClientRect(); return toWorld(r.left + r.width / 2, r.top + r.height / 2); };

  function draw() {
    for (const c of [...world.querySelectorAll(".cv-card")]) c.remove();
    for (const n of data.nodes) world.appendChild(cardEl(n));
    drawEdges();
    applyView();
  }
  function nodeById(id) { return data.nodes.find((n) => n.id === id); }
  function anchor(a, b) {
    // a の枠の上で、b の中心へ向かう点
    const ax = a.x + a.w / 2, ay = a.y + a.h / 2, bx = b.x + b.w / 2, by = b.y + b.h / 2;
    const dx = bx - ax, dy = by - ay;
    if (!dx && !dy) return { x: ax, y: ay };
    const t = Math.min(Math.abs((a.w / 2) / (dx || 1e-9)), Math.abs((a.h / 2) / (dy || 1e-9)));
    return { x: ax + dx * t, y: ay + dy * t };
  }
  function drawEdges() {
    svg.textContent = "";
    const NS = "http://www.w3.org/2000/svg";
    const defs = document.createElementNS(NS, "defs");
    defs.innerHTML = '<marker id="cv-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="currentColor"/></marker>';
    svg.appendChild(defs);
    for (const e of data.edges) {
      const a = nodeById(e.from), b = nodeById(e.to);
      if (!a || !b) continue;
      const p = anchor(a, b), q = anchor(b, a);
      const g = document.createElementNS(NS, "g"); g.classList.add("cv-edge"); if (selEdge === e.id) g.classList.add("sel");
      const hit = document.createElementNS(NS, "line");
      for (const [k, v] of [["x1", p.x], ["y1", p.y], ["x2", q.x], ["y2", q.y]]) hit.setAttribute(k, v);
      hit.classList.add("cv-hit");
      const ln = hit.cloneNode(); ln.classList.remove("cv-hit"); ln.classList.add("cv-line"); ln.setAttribute("marker-end", "url(#cv-arrow)");
      g.append(hit, ln);
      if (e.label) {
        const t = document.createElementNS(NS, "text"); t.setAttribute("x", (p.x + q.x) / 2); t.setAttribute("y", (p.y + q.y) / 2 - 4); t.classList.add("cv-elabel"); t.textContent = e.label;
        g.appendChild(t);
      }
      g.addEventListener("mousedown", (ev) => { ev.stopPropagation(); selEdge = e.id; selected.clear(); markSel(); drawEdges(); });
      g.addEventListener("dblclick", async (ev) => {
        ev.stopPropagation();
        const v = await form({ title: "矢印の名前", fields: [{ key: "label", label: "名前", value: e.label || "", placeholder: "例: 栽培・きっかけ" }] });
        if (v) { e.label = v.label.trim(); drawEdges(); schedule(); }
      });
      svg.appendChild(g);
    }
    if (linking) {
      const a = nodeById(linking.from);
      if (a) {
        const ln = document.createElementNS(NS, "line"); ln.classList.add("cv-line", "temp");
        ln.setAttribute("x1", a.x + a.w); ln.setAttribute("y1", a.y + a.h / 2); ln.setAttribute("x2", linking.x); ln.setAttribute("y2", linking.y);
        svg.appendChild(ln);
      }
    }
  }
  function markSel() { for (const c of world.querySelectorAll(".cv-card")) c.classList.toggle("sel", selected.has(c.dataset.id)); }

  function cardEl(n) {
    const c = h("div", "cv-card " + n.type);
    c.dataset.id = n.id;
    Object.assign(c.style, { left: n.x + "px", top: n.y + "px", width: n.w + "px", height: n.h + "px" });
    if (n.color) c.style.setProperty("--card", n.color);
    if (selected.has(n.id)) c.classList.add("sel");
    if (n.type === "note") {
      c.appendChild(h("div", "cv-ctitle", titles[n.file] || n.file));
      c.appendChild(h("div", "cv-cprev", previews[n.file] || ""));
      const tools = h("div", "cv-ctools");
      tools.append(button("開く", () => ctx.open(n.file), "md-tool"), button("索引を広げる", () => expandTopics(n), "md-tool", "このノートのトピック索引の項目をカードで周りに並べる"));
      c.appendChild(tools);
    } else {
      const t = h("div", "cv-ctext", n.text || "");
      c.appendChild(t);
    }
    const dot = h("div", "cv-port"); dot.title = "引いて別のカードへ（矢印）";
    const rs = h("div", "cv-resize"); rs.title = "大きさ";
    c.append(dot, rs);
    // 移動
    c.addEventListener("mousedown", (e) => {
      if (e.target.closest("button") || e.target === dot || e.target === rs || e.target.tagName === "TEXTAREA") return;
      e.stopPropagation();
      if (!e.shiftKey && !selected.has(n.id)) selected.clear();
      selected.add(n.id); selEdge = null; markSel(); drawEdges();
      const start = toWorld(e.clientX, e.clientY);
      const orig = [...selected].map((id) => { const m = nodeById(id); return { m, x: m.x, y: m.y }; });
      let moved = false;
      const mv = (ev) => {
        const p = toWorld(ev.clientX, ev.clientY);
        for (const o of orig) { o.m.x = Math.round(o.x + p.x - start.x); o.m.y = Math.round(o.y + p.y - start.y); const ce = world.querySelector(`.cv-card[data-id="${o.m.id}"]`); if (ce) { ce.style.left = o.m.x + "px"; ce.style.top = o.m.y + "px"; } }
        moved = true; drawEdges();
      };
      const up = () => { document.removeEventListener("mousemove", mv, true); document.removeEventListener("mouseup", up, true); if (moved) schedule(); };
      document.addEventListener("mousemove", mv, true); document.addEventListener("mouseup", up, true);
    });
    // 大きさ
    rs.addEventListener("mousedown", (e) => {
      e.stopPropagation();
      const start = toWorld(e.clientX, e.clientY), w0 = n.w, h0 = n.h;
      const mv = (ev) => { const p = toWorld(ev.clientX, ev.clientY); n.w = Math.max(80, Math.round(w0 + p.x - start.x)); n.h = Math.max(40, Math.round(h0 + p.y - start.y)); c.style.width = n.w + "px"; c.style.height = n.h + "px"; drawEdges(); };
      const up = () => { document.removeEventListener("mousemove", mv, true); document.removeEventListener("mouseup", up, true); schedule(); };
      document.addEventListener("mousemove", mv, true); document.addEventListener("mouseup", up, true);
    });
    // 矢印
    dot.addEventListener("mousedown", (e) => {
      e.stopPropagation();
      linking = { from: n.id, ...toWorld(e.clientX, e.clientY) };
      const mv = (ev) => { Object.assign(linking, toWorld(ev.clientX, ev.clientY)); drawEdges(); };
      const up = (ev) => {
        document.removeEventListener("mousemove", mv, true); document.removeEventListener("mouseup", up, true);
        const target = document.elementFromPoint(ev.clientX, ev.clientY)?.closest(".cv-card");
        const to = target && target.dataset.id;
        linking = null;
        if (to && to !== n.id && !data.edges.some((x) => x.from === n.id && x.to === to)) { data.edges.push({ id: newId("e"), from: n.id, to }); schedule(); }
        drawEdges();
      };
      document.addEventListener("mousemove", mv, true); document.addEventListener("mouseup", up, true);
    });
    // 開く・直す
    c.addEventListener("dblclick", async (e) => {
      e.stopPropagation();
      if (n.type === "note") { ctx.open(n.file); return; }
      editText(n, c);
    });
    c.addEventListener("contextmenu", (e) => {
      e.preventDefault(); e.stopPropagation();
      colorMenu(n, e.clientX, e.clientY);
    });
    return c;
  }

  function editText(n, c) {
    const t = c.querySelector(".cv-ctext");
    const ta = h("textarea", "cv-edit"); ta.value = n.text || "";
    t.replaceWith(ta); ta.focus();
    const done = () => { n.text = ta.value; const nt = h("div", "cv-ctext", n.text); ta.replaceWith(nt); schedule(); };
    ta.addEventListener("blur", done, { once: true });
    ta.addEventListener("keydown", (e) => { if (e.key === "Escape" || (e.key === "Enter" && (e.ctrlKey || e.metaKey))) { e.preventDefault(); ta.blur(); } e.stopPropagation(); });
  }

  function colorMenu(n, x, y) {
    document.querySelectorAll(".ctxmenu").forEach((m) => m.remove());
    const m = h("div", "ctxmenu cv-colors"); m.style.left = x + "px"; m.style.top = y + "px";
    for (const col of COLORS) {
      const b = button(col ? "●" : "○ 色なし", () => { n.color = col; m.remove(); draw(); schedule(); });
      if (col) b.style.color = col;
      m.appendChild(b);
    }
    m.appendChild(h("div", "sep"));
    m.appendChild(button("消す", () => { m.remove(); removeNodes([n.id]); }));
    document.body.appendChild(m);
    const away = (e) => { if (!m.contains(e.target)) { m.remove(); document.removeEventListener("mousedown", away, true); } };
    setTimeout(() => document.addEventListener("mousedown", away, true), 0);
  }

  function removeNodes(ids) {
    const s = new Set(ids);
    data.nodes = data.nodes.filter((n) => !s.has(n.id));
    data.edges = data.edges.filter((e) => !s.has(e.from) && !s.has(e.to));
    selected.clear(); draw(); schedule();
  }

  async function addNote(at) {
    const v = await form({
      title: "ノートを置く", ok: "置く",
      fields: [{ key: "file", label: "ノート", type: "picker", placeholder: "題で探す", load: async (s) => { const r = await ctx.query("nav.notes", { q: s }); return (r.ok ? r.result : []).filter((x) => x.rel !== rel).map((x) => ({ value: x.rel, label: x.title, sub: noteSub(x) })); } }],
    });
    if (!v || !v.file) return;
    const p = at || center();
    await placeNote(v.file, p.x - 110, p.y - 50);
    draw(); schedule();
  }
  async function placeNote(file, x, y) {
    await fetchTitles([file]);
    const ex = data.nodes.find((n) => n.type === "note" && n.file === file);
    if (ex) return ex;
    const n = { id: newId("n"), type: "note", file, x: Math.round(x), y: Math.round(y), w: 220, h: 110 };
    data.nodes.push(n);
    return n;
  }
  function addText(at) {
    const p = at || center();
    const n = { id: newId("t"), type: "text", text: "", x: Math.round(p.x - 90), y: Math.round(p.y - 30), w: 180, h: 70 };
    data.nodes.push(n);
    draw();
    const c = world.querySelector(`.cv-card[data-id="${n.id}"]`);
    if (c) editText(n, c);
  }

  // ダブルインデックスを図に: ノートのトピック索引の項目を、名前つきの矢印でまわりに並べる
  async function expandTopics(n) {
    const r = await ctx.query("nav.topics", { file: n.file });
    const items = [];
    for (const t of (r.ok ? r.result : [])) for (const e of t.entries) if (e.rel && !e.missing) items.push(e);
    if (!items.length) { toast("このノートにはトピック索引の項目がありません"); return; }
    const cx = n.x + n.w / 2, cy = n.y + n.h / 2, R = 260 + items.length * 8;
    let i = 0;
    for (const e of items) {
      const ang = (2 * Math.PI * i) / items.length - Math.PI / 2;
      const m = await placeNote(e.rel, cx + R * Math.cos(ang) - 110, cy + R * Math.sin(ang) - 55);
      if (!data.edges.some((x) => x.from === n.id && x.to === m.id)) data.edges.push({ id: newId("e"), from: n.id, to: m.id, label: e.label });
      i++;
    }
    draw(); schedule();
  }

  // ---- 背景の操作（パン・選択の解除・ダブルクリックで文字のカード・ホイールで拡大縮小） ----
  stage.addEventListener("mousedown", (e) => {
    if (e.target.closest(".cv-card") || e.target.closest(".cv-edge")) return;
    selected.clear(); selEdge = null; markSel(); drawEdges();
    const sx = e.clientX, sy = e.clientY, vx = view.x, vy = view.y;
    const mv = (ev) => { view.x = vx + ev.clientX - sx; view.y = vy + ev.clientY - sy; applyView(); };
    const up = () => { document.removeEventListener("mousemove", mv, true); document.removeEventListener("mouseup", up, true); };
    document.addEventListener("mousemove", mv, true); document.addEventListener("mouseup", up, true);
  });
  stage.addEventListener("dblclick", (e) => { if (e.target.closest(".cv-card")) return; addText(toWorld(e.clientX, e.clientY)); });
  stage.addEventListener("wheel", (e) => {
    e.preventDefault();
    const r = stage.getBoundingClientRect();
    if (e.ctrlKey || Math.abs(e.deltaY) > Math.abs(e.deltaX) && !e.shiftKey) zoom(e.deltaY < 0 ? 1.1 : 1 / 1.1, e.clientX - r.left, e.clientY - r.top);
    else { view.x -= e.deltaX; view.y -= e.deltaY; applyView(); }
  }, { passive: false });
  // サイドバー・索引ブラウザのノートを落として置く（text/gnosis-note に vault からの相対パス）
  stage.addEventListener("dragover", (e) => { if ([...e.dataTransfer.types].includes("text/gnosis-note")) e.preventDefault(); });
  stage.addEventListener("drop", async (e) => {
    const f = e.dataTransfer.getData("text/gnosis-note");
    if (!f) return;
    e.preventDefault();
    const p = toWorld(e.clientX, e.clientY);
    await placeNote(f, p.x - 110, p.y - 55); draw(); schedule();
  });
  el.addEventListener("keydown", (e) => {
    if (e.target.tagName === "TEXTAREA" || e.target.tagName === "INPUT") return;
    if ((e.key === "Delete" || e.key === "Backspace") && (selected.size || selEdge)) {
      e.preventDefault();
      if (selEdge) { data.edges = data.edges.filter((x) => x.id !== selEdge); selEdge = null; drawEdges(); schedule(); }
      else removeNodes([...selected]);
    } else if (e.key === "f") fit();
    else if (e.key === "n") { e.preventDefault(); addNote(); }
    else if (e.key === "t") { e.preventDefault(); addText(); }
  });

  load().then(() => setTimeout(fit, 0));
  return { el, loaded: true, onShow: () => { if (!dirty) load(); } };
}
