// タブ・分割ペインの画面（レイアウトの木は layout.js。ここは DOM と操作）。
//   - タブの種類: vim（今の #stage をそのまま入れる。ちょうど 1 つ）と、表示専用ビュー（書き出した静的サイトのページを iframe で）。
//   - 表示専用ビューは書き込まない。ノートを編集したいときは Vim のタブで開く（iframe 内のノートへのリンクは親へ知らせる: bridge.js）。
//   - ドラッグでタブの並べ替え・別のペインへの移動・端へ落として分割。分割線のドラッグでリサイズ。右クリックのメニューでも同じ操作。
//   - レイアウトは vault ごとに .gnosis/workspace.json に保存し、次回に復元する（閉じたタブの再開用の履歴も）。
import * as L from "./layout.js";
import { EXTRA_VIEWS, EXTRA_KEYS, extraTitle } from "./extra-views.js";
import { rank } from "./palette-core.js";

export const KIND_LABEL = { vim: "Vim", index: "一覧", analysis: "分析", cards: "カード", table: "テーブル", timeline: "タイムライン", graph: "グラフ", fznav: "番号ナビ", search: "検索", note: "ノート", v2: "追加ビュー", features: "機能一覧" };
const PAGES = { index: "index.html", analysis: "analysis.html", cards: "cards.html", table: "table.html", timeline: "timeline.html", graph: "graph.html", fznav: "fznav.html", search: "search.html" };
export const VIEW_KINDS = ["cards", "table", "timeline", "graph", "fznav", "analysis", "search", "index"];

function pageFor(tab) {
  const p = tab.params || {};
  if (tab.kind === "note") return (p.rel || "index.md").replace(/\.md$/i, ".html").split("/").map(encodeURIComponent).join("/");
  if (tab.kind === "v2") return EXTRA_KEYS.has(p.key) ? `${p.key}.html` : "views.html";        // 知らないキー(古い保存・手書き)は一覧ページへ
  const base = PAGES[tab.kind] || "index.html";
  if (tab.kind === "graph" && p.n) return `${base}#n=${encodeURIComponent(p.n)}&depth=${p.depth || 1}`;
  if (tab.kind === "fznav" && p.id) return `${base}#id=${encodeURIComponent(p.id)}`;
  if (tab.kind === "search" && p.q) return `${base}#q=${encodeURIComponent(p.q)}`;
  return base;
}

export function createPanes({ root, stageEl, gui, onNote, onResize, onChange, featureItems }) {
  let layout = L.newLayout();
  const closed = L.createClosedStack();
  let focusPane = L.panes(layout)[0].id;
  let siteUrl = "";
  let sig = "";
  let saveTimer = null;
  const els = new Map();            // タブ id → { el, frame?, loaded }
  const paneEls = new Map();        // ペイン id → { pane, bar, body, zone }
  const splitEls = new Map();       // 分割 id → { split, a, b, splitter }
  const h = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };

  // ---- 永続化 ----
  function save() { clearTimeout(saveTimer); saveTimer = setTimeout(() => { gui.saveWorkspace(JSON.stringify({ version: 1, layout, closed: closed.toJSON() })); }, 500); }
  function changed() { render(); save(); onChange && onChange(layout); }

  // ---- 表示専用ビューの中身 ----
  async function ensureSite(force) {
    const r = await gui.viewSite(!!force);
    if (!r.ok) throw new Error(r.error || "ビューの元になるサイトを作れませんでした");
    siteUrl = r.url;
    return siteUrl;
  }
  function makeEl(tab) {
    if (tab.kind === "vim") return { el: stageEl, loaded: true };
    if (tab.kind === "features") return makeFeatures(tab);
    const el = h("div", "viewbox");
    const strip = h("div", "viewstrip");
    const refresh = h("button", "", "更新"); refresh.type = "button"; refresh.title = "ノートの最新の状態でビューを作り直す";
    refresh.addEventListener("click", async () => { try { await ensureSite(true); reloadAll(); } catch (e) { setMsg(entry, String(e.message || e)); } });
    strip.appendChild(refresh);
    if (tab.kind === "note") {
      const edit = h("button", "", "編集（Vim）で開く"); edit.type = "button";
      edit.addEventListener("click", () => onNote && onNote((tab.params.rel || "").replace(/\.html$/i, ".md")));
      strip.appendChild(edit);
    }
    const msg = h("div", "viewmsg", "読み込み中…");
    const frame = document.createElement("iframe");
    frame.className = "viewframe";
    frame.name = tab.kind === "note" ? "gnosis:read" : "gnosis:open";
    frame.setAttribute("title", KIND_LABEL[tab.kind] || tab.kind);
    el.append(strip, msg, frame);
    const entry = { el, frame, msg, loaded: false, tab };
    return entry;
  }
  // ---- 機能一覧（全機能をグループ別に見せ、クリックで実行する。コマンドパレットと同じ項目） ----
  function makeFeatures(tab) {
    const el = h("div", "viewbox featbox");
    const head = h("div", "feathead");
    const input = document.createElement("input"); input.type = "search"; input.className = "featsearch";
    input.placeholder = "機能を検索（例: グラフ / 分割 / スマホ / タスク）"; input.setAttribute("aria-label", "機能を検索");
    const hint = h("div", "feathint", "項目をクリックすると実行します。ビューは新しいタブで開き、Vim のコマンドは Vim に入力します。（コマンドパレットは Ctrl+Shift+P）");
    head.append(input, hint);
    const list = h("div", "featlist");
    el.append(head, list);
    let items = [];
    function draw() {
      const q = input.value.trim();
      const shown = q ? rank(items, q, 2000) : items;
      list.textContent = "";
      const groups = new Map();
      for (const it of shown) { if (!groups.has(it.group)) groups.set(it.group, []); groups.get(it.group).push(it); }
      if (!shown.length) list.appendChild(h("div", "featnone", "見つかりません"));
      for (const [g, its] of groups) {
        const d = document.createElement("details"); d.className = "featgroup";
        d.open = !!q || g !== "Vim";                              // Vim のコマンドは数が多いので、普段は畳んでおく(検索すると開く)
        d.appendChild(h("summary", "", `${g}（${its.length}）`));
        const grid = h("div", "featgrid");
        for (const it of its) {
          const b = h("button", "featitem", it.label); b.type = "button"; b.title = it.label;
          b.addEventListener("click", async () => {
            try { await it.run(); hint.textContent = "実行しました: " + it.label; } catch (e) { hint.textContent = "実行できませんでした: " + String((e && e.message) || e); }
          });
          grid.appendChild(b);
        }
        d.appendChild(grid); list.appendChild(d);
      }
    }
    async function refresh() { try { items = featureItems ? await featureItems() : []; } catch { items = []; } draw(); }
    input.addEventListener("input", draw);
    refresh();
    return { el, loaded: true, tab, features: true, refresh };
  }
  function setMsg(entry, text) { entry.msg.textContent = text; entry.msg.hidden = !text; }
  async function load(tab) {
    const entry = els.get(tab.id);
    if (!entry || entry.loaded || tab.kind === "vim" || tab.kind === "features") return;
    entry.loaded = true;
    try {
      const base = await ensureSite(false);
      entry.frame.src = base + pageFor(tab);
      entry.frame.addEventListener("load", () => setMsg(entry, ""), { once: true });
    } catch (e) { entry.loaded = false; setMsg(entry, "ビューを作れませんでした: " + String((e && e.message) || e)); }
  }
  function reloadAll() { for (const [id, e] of els) { if (e.frame && e.loaded) { const f = L.findTab(layout, id); if (f) e.frame.src = siteUrl + pageFor(f.tab); } } }

  // ブリッジ: 埋め込んだページがノートのリンクをクリックしたら、そのノートを Vim で開く
  window.addEventListener("message", (e) => {
    const d = e.data;
    if (!d || d.gnosis !== "open" || typeof d.url !== "string") return;
    let ok = false;
    for (const [, v] of els) if (v.frame && v.frame.contentWindow === e.source) ok = true;
    if (!ok || !siteUrl || !d.url.startsWith(siteUrl)) return;
    const rel = decodeURIComponent(d.url.slice(siteUrl.length).split("#")[0]).replace(/\.html$/i, ".md");
    if (rel && !rel.includes("..")) onNote && onNote(rel);
  });

  // ---- 描画 ----
  const structureSig = (n) => (n.type === "split" ? `S${n.id}${n.dir}(${structureSig(n.a)}|${structureSig(n.b)})` : `P${n.id}`);

  function rebuild() {
    // タブの中身は一度外して付け直す（Vim の画面は消さない）
    for (const [, e] of els) if (e.el.parentNode) e.el.parentNode.removeChild(e.el);
    root.textContent = "";
    paneEls.clear(); splitEls.clear();
    root.appendChild(build(layout));
  }
  function build(n) {
    if (n.type === "tabs") {
      const pane = h("div", "pane"); pane.dataset.paneId = n.id;
      const bar = h("div", "tabbar"); const body = h("div", "panebody"); const zone = h("div", "dropzone"); zone.hidden = true;
      body.appendChild(zone);
      pane.append(bar, body);
      paneEls.set(n.id, { pane, bar, body, zone });
      pane.addEventListener("mousedown", () => { focusPane = n.id; markFocus(); }, true);
      wireDrop(n.id, bar, body, zone);
      return pane;
    }
    const split = h("div", "split " + n.dir);
    const a = build(n.a), b = build(n.b);
    const splitter = h("div", "splitter " + n.dir); splitter.dataset.splitId = n.id;
    split.append(a, splitter, b);
    splitEls.set(n.id, { split, a, b, splitter });
    wireSplitter(n, split, splitter);
    return split;
  }
  function markFocus() { for (const [id, p] of paneEls) p.pane.classList.toggle("focus", id === focusPane && paneEls.size > 1); }

  function render() {
    const s = structureSig(layout);
    if (s !== sig) { rebuild(); sig = s; }
    // ペインがなくなっていたらフォーカスを直す
    if (!paneEls.has(focusPane)) focusPane = L.panes(layout)[0].id;
    const solo = paneEls.size === 1 && L.panes(layout)[0].tabs.length === 1;
    root.classList.toggle("solo", solo);                           // Vim だけのときはタブバーを出さない（今までと同じ見た目）
    // 分割の比率
    L.walk(layout, (n) => { if (n.type !== "split") return; const e = splitEls.get(n.id); if (!e) return; e.a.style.flex = `0 0 calc(${n.ratio * 100}% - 3px)`; e.b.style.flex = "1 1 0"; });
    for (const pane of L.panes(layout)) {
      const pe = paneEls.get(pane.id);
      renderBar(pane, pe);
      for (const tab of pane.tabs) {
        let ent = els.get(tab.id);
        if (!ent) { ent = makeEl(tab); els.set(tab.id, ent); }
        if (ent.el.parentNode !== pe.body) pe.body.appendChild(ent.el);
        const visible = pane.active === tab.id;
        ent.el.style.display = visible ? "" : "none";
        if (tab.kind === "vim") { ent.el.classList.toggle("hidden-tab", !visible); }
        if (visible) load(tab);
      }
    }
    // 無くなったタブの要素を片付ける
    const live = new Set(L.panes(layout).flatMap((p) => p.tabs.map((t) => t.id)));
    for (const [id, e] of els) if (!live.has(id)) { if (e.el !== stageEl && e.el.parentNode) e.el.parentNode.removeChild(e.el); if (e.el !== stageEl) els.delete(id); }
    markFocus();
    onResize && requestAnimationFrame(() => onResize());
  }

  function renderBar(pane, pe) {
    pe.bar.textContent = "";
    for (const tab of pane.tabs) {
      const t = h("div", "tab" + (pane.active === tab.id ? " active" : "") + (tab.pinned ? " pinned" : ""));
      t.draggable = true; t.dataset.tabId = tab.id; t.title = KIND_LABEL[tab.kind] || tab.kind;
      t.appendChild(h("span", "tabtitle", (tab.pinned ? "📌 " : "") + (tab.title || KIND_LABEL[tab.kind] || tab.kind)));
      if (tab.kind !== "vim") {
        const x = h("button", "tabclose", "×"); x.type = "button"; x.title = tab.pinned ? "固定されています（右クリックで解除）" : "閉じる"; x.disabled = !!tab.pinned;
        x.addEventListener("click", (e) => { e.stopPropagation(); closeTab(tab.id); });
        t.appendChild(x);
      }
      t.addEventListener("click", () => { focusPane = pane.id; layout = L.activateTab(layout, tab.id); changed(); });
      t.addEventListener("auxclick", (e) => { if (e.button === 1) closeTab(tab.id); });
      t.addEventListener("contextmenu", (e) => { e.preventDefault(); menu(e.clientX, e.clientY, tabMenu(tab, pane)); });
      t.addEventListener("dragstart", (e) => { e.dataTransfer.setData("text/gnosis-tab", tab.id); e.dataTransfer.effectAllowed = "move"; });
      pe.bar.appendChild(t);
    }
    const plus = h("button", "tabplus", "＋"); plus.type = "button"; plus.title = "ビューを開く";
    plus.addEventListener("click", (e) => { const r = plus.getBoundingClientRect(); menu(r.left, r.bottom, [{ label: "☰ 機能一覧", run: () => { focusPane = pane.id; openFeatures(); } }, "-", ...VIEW_KINDS.map((k) => ({ label: KIND_LABEL[k], run: () => { focusPane = pane.id; openView(k); } })), "-", { label: "その他のビュー…", run: () => { focusPane = pane.id; extraMenu(r.left, r.bottom); } }]); e.stopPropagation(); });
    pe.bar.appendChild(plus);
  }

  // ---- 右クリックのメニュー（ドラッグが使えない人・タッチでも同じ操作） ----
  function menu(x, y, items) {
    document.querySelectorAll(".ctxmenu").forEach((m) => m.remove());
    const m = h("div", "ctxmenu"); m.style.left = x + "px"; m.style.top = y + "px";
    for (const it of items) {
      if (it === "-") { m.appendChild(h("div", "sep")); continue; }
      const b = h("button", "", it.label); b.type = "button"; b.disabled = !!it.disabled;
      b.addEventListener("click", () => { m.remove(); it.run(); });
      m.appendChild(b);
    }
    document.body.appendChild(m);
    // 画面からはみ出さないように: 高さは画面に収めて(あふれたらスクロール)、右端・下端では内側へ寄せる
    m.style.maxHeight = (window.innerHeight - 16) + "px";
    const r = m.getBoundingClientRect();
    if (r.bottom > window.innerHeight - 8) m.style.top = Math.max(8, window.innerHeight - r.height - 8) + "px";
    if (r.right > window.innerWidth - 8) m.style.left = Math.max(8, window.innerWidth - r.width - 8) + "px";
    const away = (e) => { if (!m.contains(e.target)) { m.remove(); document.removeEventListener("mousedown", away, true); } };
    setTimeout(() => document.addEventListener("mousedown", away, true), 0);
  }
  function tabMenu(tab, pane) {
    const others = L.panes(layout).filter((p) => p.id !== pane.id);
    return [
      { label: tab.pinned ? "固定を解除" : "タブを固定", run: () => { layout = L.setPinned(layout, tab.id, !tab.pinned); changed(); } },
      { label: "閉じる", disabled: tab.kind === "vim" || tab.pinned, run: () => closeTab(tab.id) },
      "-",
      { label: "右に分割", disabled: pane.tabs.length < 2, run: () => { layout = L.splitWithTab(layout, pane.id, "row", tab.id); changed(); } },
      { label: "下に分割", disabled: pane.tabs.length < 2, run: () => { layout = L.splitWithTab(layout, pane.id, "col", tab.id); changed(); } },
      ...others.map((p, i) => ({ label: `ペイン ${L.panes(layout).findIndex((q) => q.id === p.id) + 1} へ移す`, run: () => { layout = L.moveTab(layout, tab.id, p.id); changed(); } })),
    ];
  }

  // ---- ドラッグ（タブの並べ替え・移動・端に落として分割） ----
  function dropZone(e, body) {
    const r = body.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width, y = (e.clientY - r.top) / r.height;
    if (x < 0.25) return "left"; if (x > 0.75) return "right"; if (y < 0.25) return "top"; if (y > 0.75) return "bottom";
    return "center";
  }
  function wireDrop(paneId, bar, body, zone) {
    const isTab = (e) => e.dataTransfer && [...e.dataTransfer.types].includes("text/gnosis-tab");
    bar.addEventListener("dragover", (e) => { if (isTab(e)) e.preventDefault(); });
    bar.addEventListener("drop", (e) => {
      if (!isTab(e)) return; e.preventDefault();
      const id = e.dataTransfer.getData("text/gnosis-tab");
      const tabs = [...bar.querySelectorAll(".tab")];
      let index = tabs.length;
      for (let i = 0; i < tabs.length; i++) { const r = tabs[i].getBoundingClientRect(); if (e.clientX < r.left + r.width / 2) { index = i; break; } }
      layout = L.moveTab(layout, id, paneId, index); changed();
    });
    body.addEventListener("dragover", (e) => {
      if (!isTab(e)) return; e.preventDefault();
      const z = dropZone(e, body);
      zone.hidden = false; zone.dataset.zone = z;
    });
    body.addEventListener("dragleave", (e) => { if (!body.contains(e.relatedTarget)) zone.hidden = true; });
    body.addEventListener("drop", (e) => {
      if (!isTab(e)) return; e.preventDefault();
      zone.hidden = true;
      const id = e.dataTransfer.getData("text/gnosis-tab");
      const z = dropZone(e, body);
      if (z === "center") layout = L.moveTab(layout, id, paneId);
      else layout = L.splitWithTab(layout, paneId, z === "left" || z === "right" ? "row" : "col", id, z === "left" || z === "top" ? "before" : "after");
      changed();
    });
  }

  // ---- 分割線のドラッグ ----
  function wireSplitter(n, split, splitter) {
    splitter.addEventListener("mousedown", (e) => {
      e.preventDefault();
      const r = split.getBoundingClientRect();
      const move = (ev) => {
        const ratio = n.dir === "row" ? (ev.clientX - r.left) / r.width : (ev.clientY - r.top) / r.height;
        layout = L.setRatio(layout, n.id, ratio);
        const cur = splitEls.get(n.id); const rr = L.setRatio(layout, n.id, ratio);
        let val = ratio; L.walk(rr, (x) => { if (x.id === n.id) val = x.ratio; });
        cur.a.style.flex = `0 0 calc(${val * 100}% - 3px)`;
      };
      const up = () => { document.removeEventListener("mousemove", move, true); document.removeEventListener("mouseup", up, true); save(); onResize && onResize(); };
      document.addEventListener("mousemove", move, true); document.addEventListener("mouseup", up, true);
    });
  }

  // ---- 操作（ボタン・メニュー・キー・パレットが同じものを呼ぶ） ----
  function openFeatures() { openView("features", {}, "機能一覧"); }
  function openExtra(key) { openView("v2", { key }, extraTitle(key)); }
  function extraMenu(x, y) { menu(x, y, EXTRA_VIEWS.map(([k, t]) => ({ label: t, run: () => { openExtra(k); } }))); }
  function openView(kind, params = {}, title = "") {
    layout = L.openTab(layout, paneEls.has(focusPane) ? focusPane : L.panes(layout)[0].id, L.newTab(kind, { title: title || KIND_LABEL[kind] || kind, params }));
    changed();
  }
  function closeTab(id) {
    const r = L.closeTab(layout, id);
    if (!r.closed) return false;
    layout = r.layout; closed.push(r.closed); changed();
    return true;
  }
  function reopenClosed() {
    const c = closed.pop();
    if (!c) return false;
    layout = L.reopen(layout, c, paneEls.has(focusPane) ? focusPane : undefined); changed();
    return true;
  }
  // 今のペインを分ける。新しい側には、直前に使った種類のビュー（無ければカード）を開く
  function splitFocused(dir, kind = "cards") {
    const pane = L.findPane(layout, paneEls.has(focusPane) ? focusPane : L.panes(layout)[0].id);
    layout = L.splitPane(layout, pane.id, dir, L.newTab(kind, { title: KIND_LABEL[kind] || kind }));
    changed();
  }
  function unsplitFocused() {
    if (L.panes(layout).length < 2) return false;
    layout = L.unsplit(layout, paneEls.has(focusPane) ? focusPane : L.panes(layout)[1].id); changed();
    return true;
  }
  function cycle(dir) {
    const pane = L.findPane(layout, focusPane) || L.panes(layout)[0];
    const i = pane.tabs.findIndex((t) => t.id === pane.active);
    const next = pane.tabs[(i + dir + pane.tabs.length) % pane.tabs.length];
    layout = L.activateTab(layout, next.id); changed();
  }
  function showVim() { const v = L.vimTab(layout); if (v) { focusPane = L.findTab(layout, v.id).pane.id; layout = L.activateTab(layout, v.id); changed(); } }
  function setNoteTab(rel) { openView("note", { rel }, rel.replace(/\.md$/i, "").split("/").pop()); }

  async function restore() {
    try {
      const text = await gui.loadWorkspace();
      if (text) {
        const o = JSON.parse(text);
        layout = L.restore(o.layout);
        closed.load(o.closed);
      }
    } catch { layout = L.newLayout(); }
    focusPane = L.panes(layout)[0].id;
    render();
  }

  // Vim の画面の大きさが変わるので、ペインの大きさが変わったら伝える
  if (typeof ResizeObserver !== "undefined") new ResizeObserver(() => { onResize && onResize(); }).observe(root);

  render();
  return {
    getLayout: () => layout, panesCount: () => paneEls.size, closedCount: () => closed.size(),
    openView, openExtra, openFeatures, closeTab, reopenClosed, splitFocused, unsplitFocused, cycle, showVim, setNoteTab, restore, save,
    activeKind: () => { const p = L.findPane(layout, focusPane) || L.panes(layout)[0]; return (L.findTab(layout, p.active) || {}).tab?.kind || ""; },
    focusPaneId: () => focusPane,
    activateTab: (id) => { layout = L.activateTab(layout, id); changed(); },
    reloadViews: async () => { await ensureSite(true); reloadAll(); },
  };
}
