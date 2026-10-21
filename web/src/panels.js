// 左右のバーに入れるパネル（docks.js が並べる）。どれも読むだけで、書くのは Vim（ctx.op / ctx.commit）。
//   ノート      … 全部のノート（Obsidian のファイル一覧と同じく並び替えだけ。フォルダ分けは強制しない）
//   検索        … Obsidian と同じ書き方の全文検索（当たった行に色・押すとその行へ）
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

// ---------------------------------------------------------------- ノート（Obsidian のファイル一覧と同じく、絞り込みは無し。探すのは「検索」で）
const NOTE_SORTS = [["ctime-new", "作った日時（新しい順）"], ["ctime-old", "作った日時（古い順）"], ["mtime-new", "更新日時（新しい順）"], ["mtime-old", "更新日時（古い順）"], ["name-asc", "題（A → Z・あ → ん）"], ["name-desc", "題（Z → A・ん → あ）"]];
export function notesPanel(ctx) {
  return (el) => {
    el.classList.add("pnl");
    let sort = "ctime-new";
    try { sort = localStorage.getItem("gnosis.notesSort") || sort; } catch { /* ignore */ }
    const sortBtn = button("⇅", (e) => ctx.menu(e.clientX, e.clientY, NOTE_SORTS.map(([k, t]) => ({ label: (k === sort ? "● " : "　") + t, run: () => { sort = k; try { localStorage.setItem("gnosis.notesSort", k); } catch { /* ignore */ } load(); } }))), "pnl-btn", "並び替え");
    panelHead(el, "ノート", [sortBtn, button("＋", () => ctx.newNote(), "pnl-btn", "新しいノート（Ctrl+N）")]);
    const list = h("div", "pnl-body");
    el.append(list);
    let cur = "", my = 0;
    async function load() {
      const n = ++my;
      const r = await ctx.query("nav.notes", { limit: 3000, sort });
      if (n !== my) return;
      list.textContent = "";
      const res = r.ok ? r.result : [];
      if (!res.length) { list.appendChild(h("div", "nav-empty", "ノートがありません")); return; }
      list.appendChild(h("div", "pnl-sec", (NOTE_SORTS.find(([k]) => k === sort) || [, ""])[1] + `（${res.length}${res.length >= 3000 ? "+" : ""}）`));
      for (const x of res) {
        const row = noteRow(ctx, x, x.time ? x.time.slice(0, 10) : "");
        row.dataset.rel = x.rel;
        if (cur && cur.endsWith("/" + x.rel)) row.classList.add("cur");
        list.appendChild(row);
      }
    }
    return { onShow: () => load(), refresh: () => load(), follow: (f) => { cur = f; for (const r of list.querySelectorAll(".pnl-item")) r.classList.toggle("cur", !!cur && cur.endsWith("/" + r.dataset.rel)); } };
  };
}

// ---------------------------------------------------------------- 検索（Obsidian と同じ書き方。python/obsidian_search.py）
const SEARCH_SORTS = [["name-asc", "題（A → Z）"], ["name-desc", "題（Z → A）"], ["mtime-new", "更新日時（新しい順）"], ["mtime-old", "更新日時（古い順）"], ["ctime-new", "作った日時（新しい順）"], ["ctime-old", "作った日時（古い順）"]];
const SEARCH_OPS = [
  ["file:", "ファイル名・題で探す"], ["path:", "パスで探す"], ["content:", "本文だけで探す"], ["tag:", "タグで探す"],
  ["line:()", "同じ行に全部"], ["block:()", "同じ段落に全部"], ["section:()", "同じ節（見出しの下）に全部"],
  ["task:", "チェックボックスの行"], ["task-todo:", "未完了のチェックボックス"], ["task-done:", "完了したチェックボックス"],
  ["match-case:", "大文字と小文字を区別"], ["ignore-case:", "大文字と小文字を区別しない"], ["[]", "front matter の項目（[項目:値]）"],
];
export function markText(text, ranges) {
  const out = [];
  let last = 0;
  for (const [a, b] of ranges) {
    if (a < last) continue;
    if (a > last) out.push(document.createTextNode(text.slice(last, a)));
    out.push(h("mark", "sr-hit", text.slice(a, b)));
    last = b;
  }
  if (last < text.length) out.push(document.createTextNode(text.slice(last)));
  return out;
}
export function searchPanel(ctx) {
  return (el) => {
    el.classList.add("pnl", "srch");
    const st = { q: "", case: false, sort: "name-asc", explain: false, collapsed: false };
    try { Object.assign(st, JSON.parse(localStorage.getItem("gnosis.search") || "{}"), { q: "" }); } catch { /* ignore */ }
    const keep = () => { try { localStorage.setItem("gnosis.search", JSON.stringify({ ...st, q: "" })); } catch { /* ignore */ } };
    const caseBtn = button("Aa", () => { st.case = !st.case; caseBtn.setAttribute("aria-pressed", String(st.case)); keep(); run(); }, "pnl-btn", "大文字と小文字を区別する");
    const exBtn = button("?", () => { st.explain = !st.explain; exBtn.setAttribute("aria-pressed", String(st.explain)); keep(); draw(); }, "pnl-btn", "検索語の説明を出す");
    const colBtn = button("≡", () => { st.collapsed = !st.collapsed; colBtn.setAttribute("aria-pressed", String(st.collapsed)); keep(); draw(); }, "pnl-btn", "結果を畳む（ノートの題だけ）");
    const sortBtn = button("⇅", (e) => ctx.menu(e.clientX, e.clientY, SEARCH_SORTS.map(([k, t]) => ({ label: (k === st.sort ? "● " : "　") + t, run: () => { st.sort = k; keep(); run(); } }))), "pnl-btn", "並び替え");
    caseBtn.setAttribute("aria-pressed", String(st.case)); exBtn.setAttribute("aria-pressed", String(st.explain)); colBtn.setAttribute("aria-pressed", String(st.collapsed));
    panelHead(el, "検索", [caseBtn, exBtn, colBtn, sortBtn]);
    const input = h("input", "pnl-search srch-input");
    input.type = "search"; input.placeholder = "検索…（例: 京都 -旅行・\"りんご ジャム\"・file:日記・line:(a b)）";
    input.setAttribute("aria-label", "全文検索"); input.spellcheck = false;
    const ops = h("div", "srch-ops");
    for (const [op, t] of SEARCH_OPS) {
      const b = h("button", "srch-op"); b.type = "button";
      b.append(h("code", "", op), h("span", "", t));
      b.addEventListener("mousedown", (e) => {
        e.preventDefault();
        const v = input.value.replace(/\s*$/, "");
        const ins = op.endsWith("()") ? op : op === "[]" ? "[" : op;
        input.value = (v ? v + " " : "") + ins;
        const pos = op.endsWith("()") ? input.value.length - 1 : input.value.length;
        input.focus(); input.setSelectionRange(pos, pos);
        ops.hidden = true;
      });
      ops.appendChild(b);
    }
    ops.hidden = true;
    const status = h("div", "srch-status", "");
    const exBox = h("pre", "srch-explain", "");
    const list = h("div", "pnl-body srch-list");
    el.append(input, ops, status, exBox, list);
    let res = null, my = 0, timer = null;
    const open = new Map();     // rel → 畳んでいるか（ノートごと）
    async function run() {
      const q = input.value.trim();
      st.q = q;
      if (!q) { res = null; draw(); return; }
      const n = ++my;
      const r = await ctx.query("search.full", { q, case: st.case, sort: st.sort });
      if (n !== my) return;
      res = r.ok ? r.result : { results: [], total: 0, error: r.error };
      draw();
    }
    function draw() {
      list.textContent = "";
      exBox.hidden = !(st.explain && res && res.explain);
      exBox.textContent = res && res.explain ? res.explain : "";
      if (!res) { status.textContent = ""; return; }
      if (res.error) { status.textContent = res.error; status.className = "srch-status err"; return; }
      status.className = "srch-status";
      status.textContent = res.total ? `${res.total} 件のノート` : "見つかりません";
      for (const x of res.results) {
        const box = h("div", "sr-file");
        const head = h("div", "sr-head");
        const folded = open.has(x.rel) ? open.get(x.rel) : st.collapsed;
        const tw = h("button", "sr-twisty" + (folded ? "" : " open")); tw.type = "button"; tw.setAttribute("aria-label", "開く・畳む");
        tw.appendChild(icon("chevron", 14));
        tw.addEventListener("click", () => { open.set(x.rel, !folded); draw(); });
        const t = h("button", "sr-title", x.title); t.type = "button"; t.title = x.rel;
        t.addEventListener("click", () => ctx.open(x.rel));
        head.append(tw, t, h("span", "pnl-count", String(x.count)));
        draggable(head, x.rel);
        box.appendChild(head);
        if (!folded) {
          for (const ln of x.lines) {
            const row = h("button", "sr-line"); row.type = "button"; row.title = `${ln.line} 行目`;
            row.append(...markText(ln.text, ln.ranges));
            row.addEventListener("click", () => ctx.openAt(x.rel, ln.line));
            box.appendChild(row);
          }
          if (x.more) box.appendChild(h("div", "sr-more", `ほか ${x.more} 行`));
        }
        list.appendChild(box);
      }
    }
    input.addEventListener("input", () => { clearTimeout(timer); ops.hidden = !!input.value.trim(); timer = setTimeout(run, 250); });
    input.addEventListener("focus", () => { ops.hidden = !!input.value.trim(); });
    input.addEventListener("blur", () => setTimeout(() => { ops.hidden = true; }, 150));
    input.addEventListener("keydown", (e) => {
      if (imeActive(e)) return;
      if (e.key === "Enter") { e.preventDefault(); clearTimeout(timer); ops.hidden = true; run(); }
      if (e.key === "Escape") { if (input.value) { input.value = ""; run(); } else ctx.focusVim(); }
    });
    return {
      onShow: () => {}, refresh: () => { if (st.q) run(); },
      focusSearch: (q) => { if (q != null) { input.value = q; run(); } input.focus(); input.select(); },
    };
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
