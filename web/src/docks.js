// Obsidian のような画面の枠: 左端のアイコン列（リボン）と、左右の開け閉めできるバー（サイドドック）。
//   - リボン: よく使う画面を 1 押しで開く。右クリックで、出すアイコンを選べる。いちばん上は左のバーの開け閉め。
//   - 左右のバー: 上にパネルのタブ（アイコン）。押すと切り替わり、今のパネルをもう一度押すとバーを閉じる。
//     パネルのタブはドラッグで反対側のバーへ移せる（右クリックのメニューでも）。境目のドラッグで幅を変える。
//   - 開け閉め・幅・パネルの並び・リボンのアイコンは、この PC の画面の好み（localStorage）。ノートには何も書かない。
import { h } from "./ui.js";
import { icon, iconButton } from "./icons.js";

const KEY = "gnosis.docks";
const LS = {
  get() { try { return JSON.parse(localStorage.getItem(KEY) || "null"); } catch { return null; } },
  set(v) { try { localStorage.setItem(KEY, JSON.stringify(v)); } catch { /* ignore */ } },
};

// panels: [{ id, title, icon, side: "left"|"right", create(el, api) → { onShow?(), follow?(file) } }]
// ribbon: [{ id, title, icon, run(), bottom? }]
export function createDocks({ ribbonEl, leftEl, rightEl, leftSplit, rightSplit, centerEl, panels, ribbon, onResize, menu }) {
  const byId = new Map(panels.map((p) => [p.id, p]));
  const saved = LS.get() || {};
  const st = {
    left: { open: true, width: 300, tabs: [], active: "", ...(saved.left || {}) },
    right: { open: true, width: 280, tabs: [], active: "", ...(saved.right || {}) },
    ribbonHidden: Array.isArray(saved.ribbonHidden) ? saved.ribbonHidden : [],
  };
  // 保存された並びに無いパネル（新しく増えたもの）は、決まった側の最後へ。知らない id は捨てる
  for (const side of ["left", "right"]) st[side].tabs = (st[side].tabs || []).filter((id) => byId.has(id));
  for (const p of panels) if (!st.left.tabs.includes(p.id) && !st.right.tabs.includes(p.id)) st[p.side].tabs.push(p.id);
  for (const side of ["left", "right"]) if (!st[side].tabs.includes(st[side].active)) st[side].active = st[side].tabs[0] || "";

  const inst = new Map();     // パネル id → { el, api }
  let file = "";
  const els = { left: leftEl, right: rightEl };
  const splits = { left: leftSplit, right: rightSplit };
  const heads = {}, bodies = {};
  const save = () => LS.set(st);

  // ---- リボン ----
  const leftToggle = iconButton("panel-left", "左のバーを出す・隠す", () => toggle("left"), "ribbon-toggle");
  function drawRibbon() {
    ribbonEl.textContent = "";
    const top = h("div", "ribbon-top"), bot = h("div", "ribbon-bottom");
    top.appendChild(leftToggle);
    for (const it of ribbon) {
      if (st.ribbonHidden.includes(it.id)) continue;
      const b = iconButton(it.icon, it.title, () => it.run(), "ribbon-btn");
      b.dataset.ribbon = it.id;
      (it.bottom ? bot : top).appendChild(b);
    }
    ribbonEl.append(top, bot);
  }
  ribbonEl.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    menu(e.clientX, e.clientY, ribbon.map((it) => ({
      label: (st.ribbonHidden.includes(it.id) ? "☐ " : "☑ ") + it.title,
      run: () => { const i = st.ribbonHidden.indexOf(it.id); if (i >= 0) st.ribbonHidden.splice(i, 1); else st.ribbonHidden.push(it.id); save(); drawRibbon(); },
    })));
  });

  // ---- 左右のバー ----
  const rightToggle = iconButton("panel-right", "右のバーを出す・隠す", () => toggle("right"), "dock-toggle right");
  const rightFloat = iconButton("panel-right", "右のバーを出す", () => toggle("right", true), "dock-float right");
  centerEl.appendChild(rightFloat);
  for (const side of ["left", "right"]) {
    const el = els[side];
    el.classList.add("dock", side);
    const head = h("div", "dock-head"), body = h("div", "dock-body");
    el.append(head, body);
    heads[side] = head; bodies[side] = body;
    head.addEventListener("dragover", (e) => { if ([...e.dataTransfer.types].includes("text/gnosis-panel")) { e.preventDefault(); head.classList.add("drop"); } });
    head.addEventListener("dragleave", () => head.classList.remove("drop"));
    head.addEventListener("drop", (e) => {
      head.classList.remove("drop");
      const id = e.dataTransfer.getData("text/gnosis-panel");
      if (!byId.has(id)) return;
      e.preventDefault();
      const tabs = [...head.querySelectorAll(".dock-tab")];
      let index = tabs.length;
      for (let i = 0; i < tabs.length; i++) { const r = tabs[i].getBoundingClientRect(); if (e.clientX < r.left + r.width / 2) { index = i; break; } }
      move(id, side, index);
    });
    wireSplit(side);
  }

  function wireSplit(side) {
    splits[side].addEventListener("mousedown", (e) => {
      e.preventDefault();
      const mv = (ev) => {
        const w = side === "left" ? ev.clientX - els.left.getBoundingClientRect().left : window.innerWidth - ev.clientX;
        st[side].width = Math.max(180, Math.min(700, Math.round(w)));
        apply();
      };
      const up = () => { document.removeEventListener("mousemove", mv, true); document.removeEventListener("mouseup", up, true); save(); onResize && onResize(); };
      document.addEventListener("mousemove", mv, true); document.addEventListener("mouseup", up, true);
    });
    // 境目のダブルクリックで閉じる
    splits[side].addEventListener("dblclick", () => toggle(side, false));
  }

  function ensure(id) {
    if (inst.has(id)) return inst.get(id);
    const p = byId.get(id);
    const el = h("div", "dock-panel");
    el.dataset.panel = id;
    let api = {};
    try { api = p.create(el) || {}; } catch (e) { el.appendChild(h("div", "nav-empty", "開けませんでした: " + String((e && e.message) || e))); }
    const it = { el, api, followed: "" };
    inst.set(id, it);
    return it;
  }

  function drawSide(side) {
    const s = st[side], head = heads[side], body = bodies[side];
    head.textContent = "";
    const tabs = h("div", "dock-tabs");
    for (const id of s.tabs) {
      const p = byId.get(id);
      const b = h("button", "dock-tab" + (id === s.active ? " active" : ""));
      b.type = "button"; b.title = p.title; b.setAttribute("aria-label", p.title); b.dataset.panel = id;
      b.appendChild(icon(p.icon));
      b.draggable = true;
      b.addEventListener("dragstart", (e) => { e.dataTransfer.setData("text/gnosis-panel", id); e.dataTransfer.effectAllowed = "move"; });
      b.addEventListener("click", () => { if (s.active === id && s.open) toggle(side, false); else show(id); });
      b.addEventListener("contextmenu", (e) => {
        e.preventDefault();
        const other = side === "left" ? "right" : "left";
        menu(e.clientX, e.clientY, [{ label: other === "left" ? "左のバーへ移す" : "右のバーへ移す", run: () => move(id, other) }, { label: "このバーを閉じる", run: () => toggle(side, false) }]);
      });
      tabs.appendChild(b);
    }
    if (side === "left") head.append(tabs);
    else head.append(tabs, rightToggle);
    const title = byId.get(s.active)?.title || "";
    els[side].setAttribute("aria-label", title);
    // 中身: 今のパネルだけ見せる（ほかのパネルも作ったものは残して、状態を保つ）
    for (const ch of [...body.children]) ch.hidden = ch.dataset.panel !== s.active;
    if (s.active) {
      const it = ensure(s.active);
      if (it.el.parentNode !== body) body.appendChild(it.el);
      it.el.hidden = false;
      if (s.open) showPanel(it);
    }
  }
  function showPanel(it) {
    if (it.api.follow && it.followed !== file) { it.followed = file; try { it.api.follow(file); } catch { /* ignore */ } }
    if (it.api.onShow) try { it.api.onShow(); } catch { /* ignore */ }
  }

  function apply() {
    const r = document.documentElement.style;
    for (const side of ["left", "right"]) {
      const s = st[side];
      els[side].hidden = !s.open || !s.tabs.length;
      splits[side].hidden = els[side].hidden;
      r.setProperty(`--dock-${side}-w`, s.width + "px");
    }
    rightFloat.hidden = !els.right.hidden;
    centerEl.classList.toggle("right-closed", els.right.hidden);
    leftToggle.setAttribute("aria-pressed", String(!els.left.hidden));
  }

  function render() { drawRibbon(); drawSide("left"); drawSide("right"); apply(); onResize && onResize(); }

  function sideOf(id) { return st.left.tabs.includes(id) ? "left" : st.right.tabs.includes(id) ? "right" : ""; }
  function toggle(side, on) {
    const s = st[side];
    s.open = on === undefined ? !(s.open && s.tabs.length) : !!on;
    save(); apply();
    if (s.open) drawSide(side);
    onResize && onResize();
  }
  // パネルを出す（閉じていればバーを開く）。そのパネルの API を返す
  function show(id) {
    const side = sideOf(id);
    if (!side) return null;
    st[side].active = id; st[side].open = true;
    save(); drawSide(side); apply();
    onResize && onResize();
    return inst.get(id)?.api || null;
  }
  function move(id, side, index) {
    const from = sideOf(id);
    if (!from) return;
    st[from].tabs = st[from].tabs.filter((x) => x !== id);
    if (st[from].active === id) st[from].active = st[from].tabs[0] || "";
    const t = st[side].tabs;
    t.splice(index === undefined ? t.length : Math.min(index, t.length), 0, id);
    st[side].active = id; st[side].open = true;
    save(); render();
  }
  // Vim で開いているノートが変わった: 見えているパネルだけすぐ追いかけ、ほかは見えたときに
  function follow(f) {
    file = f || "";
    for (const side of ["left", "right"]) {
      const s = st[side];
      if (!s.open || !s.active) continue;
      const it = inst.get(s.active);
      if (it && it.api.follow && it.followed !== file) { it.followed = file; try { it.api.follow(file); } catch { /* ignore */ } }
    }
  }
  // 保存のあと（索引・リンクが変わったかもしれない）: 見えているパネルを読み直す
  function refresh() {
    for (const side of ["left", "right"]) {
      const s = st[side];
      if (!s.open || !s.active) continue;
      const it = inst.get(s.active);
      if (it && it.api.refresh) try { it.api.refresh(); } catch { /* ignore */ }
    }
    for (const [id, it] of inst) if (!isVisible(id)) it.followed = "";   // 見えていないものは、次に見えたときに読み直す
  }
  function isVisible(id) { const side = sideOf(id); return !!side && st[side].open && st[side].active === id; }

  render();
  return {
    toggle, show, move, follow, refresh, isVisible,
    isOpen: (side) => !els[side].hidden,
    panel: (id) => ensure(id).api,
    state: () => JSON.parse(JSON.stringify(st)),
  };
}
