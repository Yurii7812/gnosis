// 左右のバーに入れるパネル（docks.js が並べる）。どれも読むだけで、書くのは Vim（ctx.op / ctx.commit）。
//   ノート      … 最近のノート・題で探す（Obsidian のファイル一覧の代わり。フォルダ分けは強制しない）
//   機能        … 全部の機能をグループごとに並べ、押すと実行する（コマンドパレットと同じ項目）
//   リンク      … 今のノートの関係（Context・親子・Group・トピック索引）・バックリンク・出ていくリンク
//   アウトライン … 今のノートの見出し。押すとその行へ
// ノートの行はドラッグしてキャンバス・曼荼羅のマスへ落とせる（text/gnosis-note）。
import { h, button, KIND_BADGE, noteSub, imeActive } from "./ui.js";
import { rank } from "./palette-core.js";
import { icon } from "./icons.js";

function draggable(el, rel) {
  if (!rel) return el;
  el.draggable = true;
  el.addEventListener("dragstart", (e) => { e.dataTransfer.setData("text/gnosis-note", rel); e.dataTransfer.effectAllowed = "copy"; });
  return el;
}

function panelHead(el, title, tools = []) {
  const head = h("div", "pnl-head");
  head.appendChild(h("span", "pnl-title", title));
  const t = h("span", "pnl-tools");
  for (const b of tools) t.appendChild(b);
  head.appendChild(t);
  el.appendChild(head);
  return head;
}

function noteRow(ctx, x, sub) {
  const b = h("button", "pnl-item");
  b.type = "button";
  b.title = x.rel || x.title;
  b.appendChild(h("span", "pnl-item-title", x.title));
  const badge = KIND_BADGE[x.kind];
  if (badge) b.appendChild(h("span", "pnl-badge kind-" + x.kind, badge));
  if (sub) b.appendChild(h("span", "pnl-item-sub", sub));
  if (x.missing) b.classList.add("missing");
  else b.addEventListener("click", () => ctx.open(x.rel));
  return draggable(b, x.missing ? "" : x.rel);
}

// ---------------------------------------------------------------- ノート
export function notesPanel(ctx) {
  return (el) => {
    el.classList.add("pnl");
    panelHead(el, "ノート", [button("＋", () => ctx.newNote(), "pnl-btn", "新しいノート（Ctrl+N）")]);
    const search = h("input", "pnl-search"); search.type = "search"; search.placeholder = "題で絞る";
    search.setAttribute("aria-label", "ノートを題で絞る");
    const list = h("div", "pnl-body");
    el.append(search, list);
    let timer = null, cur = "", my = 0;
    async function load() {
      const q = search.value.trim();
      const n = ++my;
      const r = await ctx.query("nav.notes", { q, limit: q ? 200 : 120 });
      if (n !== my) return;
      list.textContent = "";
      const res = r.ok ? r.result : [];
      if (!res.length) { list.appendChild(h("div", "nav-empty", q ? "見つかりません" : "ノートがありません")); return; }
      if (!q) list.appendChild(h("div", "pnl-sec", "最近のノート"));
      for (const x of res) {
        const row = noteRow(ctx, x, [x.path || "", x.time ? x.time.slice(0, 10) : ""].filter(Boolean).join(" · "));
        if (cur && cur.endsWith("/" + x.rel)) row.classList.add("cur");
        list.appendChild(row);
      }
    }
    search.addEventListener("input", () => { clearTimeout(timer); timer = setTimeout(load, 140); });
    search.addEventListener("keydown", (e) => {
      if (imeActive(e)) return;
      if (e.key === "Enter") { const f = list.querySelector(".pnl-item:not(.missing)"); if (f) f.click(); }
      if (e.key === "Escape") { search.value = ""; load(); ctx.focusVim(); }
    });
    return { onShow: () => load(), refresh: () => load(), follow: (f) => { cur = f; for (const r of list.querySelectorAll(".pnl-item")) r.classList.toggle("cur", !!cur && cur.endsWith("/" + r.title)); } };
  };
}

// ---------------------------------------------------------------- 機能
// items: async () => [{ group, label, keywords, run }]（コマンドパレットと同じ）
export function featuresPanel(getItems) {
  return (el) => {
    el.classList.add("pnl", "featpanel");
    panelHead(el, "機能");
    const search = h("input", "pnl-search"); search.type = "search"; search.placeholder = "機能を探す（例: 分割・日記・まんだら）";
    search.setAttribute("aria-label", "機能を探す");
    const list = h("div", "pnl-body");
    const msg = h("div", "pnl-msg", "");
    el.append(search, list, msg);
    let items = [], open = loadOpen();
    function loadOpen() { try { return new Set(JSON.parse(localStorage.getItem("gnosis.featOpen") || "null") || ["索引", "時間", "曼荼羅", "キャンバス", "ビュー", "バー"]); } catch { return new Set(); } }
    function saveOpen() { try { localStorage.setItem("gnosis.featOpen", JSON.stringify([...open])); } catch { /* ignore */ } }
    function draw() {
      const q = search.value.trim();
      const shown = q ? rank(items, q, 400) : items;
      list.textContent = "";
      if (!shown.length) { list.appendChild(h("div", "nav-empty", "見つかりません")); return; }
      if (q) {
        // 探しているときは、グループに分けず、合う順に並べる
        shown.forEach((it, i) => list.appendChild(itemEl(it, i === 0)));
        return;
      }
      const groups = new Map();
      for (const it of shown) { if (!groups.has(it.group)) groups.set(it.group, []); groups.get(it.group).push(it); }
      for (const [g, its] of groups) {
        const isOpen = open.has(g);
        const gh = h("button", "feat-g" + (isOpen ? " open" : ""));
        gh.type = "button";
        gh.append(icon("chevron", 14), h("span", "", g), h("span", "pnl-count", String(its.length)));
        gh.addEventListener("click", () => { if (open.has(g)) open.delete(g); else open.add(g); saveOpen(); draw(); });
        list.appendChild(gh);
        if (isOpen) for (const it of its) list.appendChild(itemEl(it));
      }
    }
    function itemEl(it, first) {
      const b = h("button", "pnl-item feat-item" + (first ? " sel" : ""));
      b.type = "button"; b.title = it.label;
      b.appendChild(h("span", "pnl-item-title", it.label));
      if (search.value.trim()) b.appendChild(h("span", "pnl-item-sub", it.group));
      b.addEventListener("click", async () => {
        try { await it.run(); msg.textContent = "実行しました: " + it.label; } catch (e) { msg.textContent = "できませんでした: " + String((e && e.message) || e); }
      });
      return b;
    }
    search.addEventListener("input", draw);
    search.addEventListener("keydown", (e) => {
      if (imeActive(e)) return;
      if (e.key === "Enter") { const f = list.querySelector(".feat-item"); if (f) f.click(); }
      if (e.key === "Escape") { search.value = ""; draw(); }
    });
    async function load() { try { items = await getItems(); } catch { items = []; } draw(); }
    return { onShow: () => load(), refresh: () => {}, focusSearch: () => { search.focus(); search.select(); } };
  };
}

// ---------------------------------------------------------------- リンク（関係・バックリンク・出ていくリンク）
export function linksPanel(ctx) {
  return (el) => {
    el.classList.add("pnl");
    panelHead(el, "リンク");
    const body = h("div", "pnl-body");
    el.appendChild(body);
    let file = "", my = 0;
    function sec(title, count) {
      const s = h("div", "pnl-sec");
      s.append(h("span", "", title));
      if (count != null) s.appendChild(h("span", "pnl-count", String(count)));
      body.appendChild(s);
    }
    async function load() {
      if (!file) { body.textContent = ""; body.appendChild(h("div", "nav-empty", "ノートを開くと、ここにリンクが出ます")); return; }
      const n = ++my;
      const r = await ctx.query("nav.links", { file });
      if (n !== my) return;
      body.textContent = "";
      const d = r.ok ? r.result : { missing: true };
      if (d.missing) { body.appendChild(h("div", "nav-empty", "このファイルは vault のノートではありません")); return; }
      const rel = [["Context（文脈）", d.context], ["ParentBranch（親）", d.parents], ["ChildBranch（子）", d.children], ["Group（載っている索引）", d.groups], ["BranchGroup（トピック索引）", d.topics]].filter(([, xs]) => xs && xs.length);
      if (rel.length) {
        sec("関係");
        for (const [t, xs] of rel) {
          body.appendChild(h("div", "pnl-sub", t));
          for (const x of xs) body.appendChild(noteRow(ctx, x, x.fz || ""));
        }
      }
      sec("バックリンク", d.backlinks.length);
      if (!d.backlinks.length) body.appendChild(h("div", "pnl-none", "このノートへリンクしているノートはありません"));
      for (const b of d.backlinks) {
        const row = noteRow(ctx, b, b.places.join("・"));
        body.appendChild(row);
        const hits = b.hits.filter((x) => x.place === "本文" && (x.row || x.text !== d.title));
        for (const hit of hits.slice(0, 2)) {
          const s = h("div", "pnl-snip");
          s.textContent = (hit.row ? hit.row + " › " : "") + hit.text;
          body.appendChild(s);
        }
      }
      sec("出ていくリンク", d.outgoing.length);
      if (!d.outgoing.length) body.appendChild(h("div", "pnl-none", "本文にリンクはありません"));
      for (const o of d.outgoing) body.appendChild(noteRow(ctx, o, o.missing ? "（まだ無いノート）" : o.text !== o.title ? "「" + o.text + "」" : ""));
    }
    return { follow: (f) => { file = f; load(); }, refresh: () => load(), onShow: () => {} };
  };
}

// ---------------------------------------------------------------- アウトライン（今のノートの見出し）
// getLines(): Vim で開いているノートの行。goto(line): その行へ
export function outlinePanel(ctx) {
  return (el) => {
    el.classList.add("pnl");
    panelHead(el, "アウトライン");
    const body = h("div", "pnl-body");
    el.appendChild(body);
    let sig = "";
    function draw(force) {
      const lines = ctx.getLines() || [];
      const heads = [];
      let fence = false, fm = lines[0] === "---";
      lines.forEach((ln, i) => {
        if (fm) { if (i > 0 && ln === "---") fm = false; return; }
        if (/^\s*(```|~~~)/.test(ln)) { fence = !fence; return; }
        if (fence) return;
        const m = /^(#{1,6})\s+(.+?)\s*#*\s*$/.exec(ln);
        if (m) heads.push({ level: m[1].length, text: m[2].replace(/\[((?:\\.|[^\]\\])*)\]\([^)]*\)/g, "$1"), line: i + 1 });
      });
      const s = JSON.stringify(heads);
      if (s === sig && !force) return;
      sig = s;
      body.textContent = "";
      if (!heads.length) { body.appendChild(h("div", "nav-empty", "見出しがありません")); return; }
      const min = Math.min(...heads.map((x) => x.level));
      for (const x of heads) {
        const b = h("button", "pnl-item outline-item");
        b.type = "button";
        b.style.paddingLeft = (8 + (x.level - min) * 14) + "px";
        b.textContent = x.text;
        b.title = `${x.line} 行目`;
        b.addEventListener("click", () => ctx.gotoLine(x.line));
        body.appendChild(b);
      }
    }
    return { onShow: () => draw(true), follow: () => draw(true), refresh: () => draw(), update: () => draw() };
  };
}
