// 索引ナビ（サイドバー）と索引ブラウザ（タブ）。ダブルインデックスを辿る・載せる・育てるための画面。
//   - いつも Vim で開いているノートに付いていく: Index からの道・載っている索引（どの名前で）・トピック索引の中身。
//   - 索引語で探す: 同じ「栽培」でも「ハーブ › 栽培」「ローズマリー › 栽培」と、どの索引の名前かが分かる形で出す。
//   - ボタン: 索引に載せる（\l の g）・トピック索引を作る（zk → n）・この索引に新しいノート（グループの上の zn → Enter）。
//     書くのは Vim（gnosis#app_op）。この画面はノートを直接書き換えない。
// データは python/app_model.py（ctx.query）。
import { h, button, form, toast, byRow, KIND_BADGE, noteSub, imeActive } from "./ui.js";

// ---------------------------------------------------------------- 共通の操作（サイドバー・索引ブラウザ・パレットから同じものを呼ぶ）
export function navActions(ctx) {
  const q = async (m, p) => { const r = await ctx.query(m, p); if (!r.ok) throw new Error(r.error || "読めませんでした"); return r.result; };
  const run = async (op, p, okText) => {
    const r = await ctx.op(op, p);
    if (!r.ok) { toast(r.error || "できませんでした", "err"); return false; }
    if (okText) toast(okText);
    ctx.changed && ctx.changed();
    return true;
  };
  const indexPicker = (exclude) => ({
    key: "group", label: "載せる索引", type: "picker", placeholder: "索引の名前で探す（空なら全部）",
    load: async (s) => {
      const all = await q("nav.indexes", {});
      const n = s.toLowerCase();
      return all.filter((x) => !exclude || !exclude.has(x.rel)).filter((x) => !n || (x.path + " " + x.title).toLowerCase().includes(n))
        .slice(0, 80).map((x) => ({ value: x.rel, label: x.is_index ? "Global Index" : x.title, sub: x.is_index ? `${x.count} 項目` : `${x.path}（${x.count} 項目）` }));
    },
  });
  return {
    q,
    // 今のノートを、選んだ索引に載せる（名前は索引語。よみは空なら推測）
    async addToIndex(info) {
      const exclude = new Set((info.indexed || []).map((x) => x.index.rel));
      const v = await form({
        title: `「${info.title}」を索引に載せる`, ok: "載せる",
        note: "索引の中の名前（索引語）は、その索引の中だけで意味が決まります。Global Index なら広い言葉、トピック索引なら短い言葉で。",
        fields: [indexPicker(exclude), { key: "name", label: "索引での名前", value: info.title, required: true }, { key: "yomi", label: "よみ", placeholder: "空なら推測（並べる順に使う）" }],
      });
      if (!v) return false;
      if (!v.group) { toast("載せる索引を選んでください", "err"); return false; }
      return run("index_add", { group: v.group, target: info.rel, name: v.name.trim(), yomi: v.yomi.trim(), back: info.rel }, `載せました: ${v.name}`);
    },
    // 今の索引（グループ）に、既存のノートを載せる
    async addExisting(info) {
      const v = await form({
        title: `索引「${info.title}」に既存のノートを載せる`, ok: "載せる",
        fields: [
          { key: "target", label: "ノート", type: "picker", placeholder: "題で探す", load: async (s) => (await q("nav.notes", { q: s })).filter((x) => x.rel !== info.rel).map((x) => ({ value: x.rel, label: x.title, sub: noteSub(x) })),
            onPick: (it, set) => set("name", it.label) },
          { key: "name", label: "索引での名前", required: true }, { key: "yomi", label: "よみ", placeholder: "空なら推測" }],
      });
      if (!v || !v.target) return false;
      return run("index_add", { group: info.rel, target: v.target, name: v.name.trim(), yomi: v.yomi.trim(), back: info.rel }, `載せました: ${v.name}`);
    },
    // 今の索引に新しいノートを作って載せる（そのまま Vim で書き始める）
    async newInIndex(info) {
      const v = await form({
        title: `索引「${info.title}」に新しいノート`, ok: "作って書く",
        note: info.origin ? `この索引の起点「${info.origin.title}」が新しいノートの親（Branch）になります。` : "",
        fields: [{ key: "name", label: "索引での名前", required: true, placeholder: "例: 栽培" }, { key: "title", label: "ノートの題", placeholder: "空なら名前と同じ" }, { key: "yomi", label: "よみ", placeholder: "空なら推測" }],
      });
      if (!v) return false;
      return run("index_new", { group: info.rel, name: v.name.trim(), title: v.title.trim(), yomi: v.yomi.trim() }, "作りました。Vim で書き始められます");
    },
    // 今のノートから分岐するトピック索引を作る
    async newTopic(info) {
      const v = await form({
        title: `「${info.title}」のトピック索引を作る`, ok: "作る",
        note: "このノートの BranchGroup: に索引ができます。Global Index のリンクは書き換えません（Index → このノート → トピック索引 → …）。",
        fields: [{ key: "title", label: "索引の題", value: info.title, required: true }],
      });
      if (!v) return false;
      return run("topic_new", { note: info.rel, title: v.title.trim() }, "トピック索引を作りました。項目を足していけます");
    },
  };
}

// ノートの本文（front matter・関係のブロックを除いた最初の 40 行ほど）。プレビュー用
const REL_HEADS = /^(BranchGroup|ThisNoteGroup|Group|ParentBranch|Context|ChildBranch|Related|BackLink):\s*$/;
export async function noteBody(ctx, rel, maxLines = 40) {
  if (!ctx.readNote) return "";
  const r = await ctx.readNote(rel);
  if (!r.ok) return "";
  let lines = r.text.split("\n");
  if (lines[0] === "---") { const e = lines.indexOf("---", 1); if (e > 0) lines = lines.slice(e + 1); }
  const out = [];
  let skip = false;
  for (const ln of lines) {
    if (!out.length && (!ln.trim() || /^#\s/.test(ln))) continue;
    if (REL_HEADS.test(ln.trim())) { skip = true; continue; }
    if (skip && /^\s*\[(?:\\.|[^\]\\])*\]\([^)]*\)\s*$/.test(ln)) continue;
    skip = false;
    out.push(ln.replace(/\[((?:\\.|[^\]\\])*)\]\([^)]*\)/g, "$1"));
    if (out.length >= maxLines) break;
  }
  return out.join("\n").replace(/\n{3,}/g, "\n\n").trim();
}

// キャンバスへ落として置けるように（text/gnosis-note に vault からの相対パス）
function draggable(el, rel) {
  if (!rel) return el;
  el.draggable = true;
  el.addEventListener("dragstart", (e) => { e.dataTransfer.setData("text/gnosis-note", rel); e.dataTransfer.effectAllowed = "copy"; });
  return el;
}

// ---------------------------------------------------------------- 道（Index › … › ここ）
function crumbEl(ctx, steps, onPick) {
  const el = h("div", "nav-crumbs");
  steps.forEach((st, i) => {
    if (st.via === "topic") return;        // ノート → 同じ名前の索引 は省く（「ハーブ › ハーブ」にならない）
    if (el.childNodes.length) el.appendChild(h("span", "nav-sep", "›"));
    const nxt = steps[i + 1];
    // 「ハーブ（索引の名前）」を押すとノートへ。トピック索引へも行けるよう、続きが topic なら小さく ▤ を付ける
    const b = button(st.label || (st.rel === "index.md" ? "Index" : st.title), () => (onPick ? onPick(st) : ctx.open(st.rel)), "nav-crumb", st.title);
    el.appendChild(b);
    if (nxt && nxt.via === "topic" && i + 1 < steps.length - 1) {
      const t = button("▤", () => (onPick ? onPick(nxt) : ctx.open(nxt.rel)), "nav-crumb-topic", `トピック索引「${nxt.title}」`);
      el.appendChild(t);
    }
  });
  return el;
}

// 項目（索引の名前）の一覧。トピック索引を持つ項目は ▸ でその場に開ける（ノートを開かずに奥へ辿れる）
function entryList(ctx, entries, depth = 0) {
  const wrap = h("div", "nav-entries");
  for (const grp of byRow(entries)) {
    const row = h("div", "nav-row");
    if (grp.row) row.appendChild(h("div", "nav-rowhead", grp.row));
    for (const e of grp.items) {
      const li = h("div", "nav-entry" + (e.missing ? " missing" : ""));
      const has = (e.topics || 0) > 0 && depth < 6;
      const tw = button(has ? "▸" : "·", () => {}, "nav-twisty" + (has ? "" : " none"), has ? "トピック索引をここで開く" : "");
      const lab = draggable(button(e.label, () => ctx.open(e.rel), "nav-label", e.title !== e.label ? `${e.label} → ${e.title}` : e.title), e.rel);
      li.append(tw, lab);
      if (e.title && e.title !== e.label) li.appendChild(h("span", "nav-title", e.title));
      if (e.group) li.appendChild(h("span", "nav-badge", "索引"));
      row.appendChild(li);
      if (has) {
        let open = false, sub = null;
        tw.addEventListener("click", async () => {
          open = !open; tw.textContent = open ? "▾" : "▸";
          if (!open) { sub && sub.remove(); sub = null; return; }
          sub = h("div", "nav-sub");
          li.after(sub);
          try {
            const r = await ctx.query("nav.topics", { file: e.rel });
            for (const t of (r.ok ? r.result : [])) {
              const head = h("div", "nav-subhead");
              head.append(button("▤ " + t.title, () => ctx.open(t.rel), "nav-label", "トピック索引を開く"), h("span", "nav-count", `${t.entries.length}`));
              sub.append(head, entryList(ctx, t.entries, depth + 1));
            }
          } catch (err) { sub.textContent = String(err); }
        });
      }
    }
    wrap.appendChild(row);
  }
  return wrap;
}

// ---------------------------------------------------------------- サイドバー
export function createNavSidebar(root, ctx) {
  const act = navActions(ctx);
  root.textContent = "";
  root.classList.add("navside");
  const head = h("div", "nav-head");
  const search = h("input", "nav-search"); search.type = "search"; search.placeholder = "索引語で探す（例: 栽培）"; search.setAttribute("aria-label", "索引語で探す");
  head.appendChild(search);
  const body = h("div", "nav-body");
  root.append(head, body);
  let info = null, file = "", busy = 0, timer = null;

  function section(title, extra) {
    const s = h("section", "nav-sec");
    const t = h("div", "nav-sectitle"); t.appendChild(h("span", "", title));
    if (extra) t.appendChild(extra);
    s.appendChild(t);
    body.appendChild(s);
    return s;
  }

  function draw() {
    body.textContent = "";
    if (!info) { body.appendChild(h("div", "nav-empty", file ? "読み込み中…" : "ノートを開くと、ここに索引の情報が出ます")); return; }
    if (info.missing) { body.appendChild(h("div", "nav-empty", "このファイルは vault のノートではありません")); return; }
    // ここ
    const me = h("div", "nav-me");
    me.appendChild(h("div", "nav-metitle", info.title));
    const badge = KIND_BADGE[info.kind];
    if (badge) me.appendChild(h("span", "nav-kind kind-" + info.kind, badge));
    if (info.fz) me.appendChild(h("span", "nav-fz", info.fz));
    body.appendChild(me);
    if (info.kind === "mandala" || info.kind === "canvas") {
      const k = info.kind;
      body.appendChild(button(k === "mandala" ? "▦ 曼荼羅の画面で開く" : "◫ キャンバスの画面で開く", () => root.dispatchEvent(new CustomEvent("gnosis-open-editor", { detail: k })), "nav-btn primary wide"));
    }
    // 道
    const s0 = section("Index からの道");
    if (info.crumbs && info.crumbs.length) s0.appendChild(crumbEl(ctx, info.crumbs[0]));
    else if (info.is_index) s0.appendChild(h("div", "nav-dim", "ここが Global Index です"));
    else {
      s0.appendChild(h("div", "nav-dim", "索引からまだ辿れません"));
      if (info.parents && info.parents.length) {
        const p = h("div", "nav-crumbs dim");
        info.parents.forEach((x, i) => { if (i) p.appendChild(h("span", "nav-sep", "›")); p.appendChild(button(x.title, () => ctx.open(x.rel), "nav-crumb")); });
        s0.appendChild(h("div", "nav-dim small", "親（ParentBranch）をたどると:"));
        s0.appendChild(p);
      }
    }
    // 索引（グループ）なら、その項目
    if (info.entries) {
      const tools = h("span", "nav-tools");
      tools.append(button("＋ 新しいノート", () => act.newInIndex(info), "nav-btn", "この索引に新しいノートを作って載せる（zn → Enter と同じ）"),
        button("＋ 既存", () => act.addExisting(info), "nav-btn", "この索引に既存のノートを載せる"));
      const s = section(`この索引の項目（${info.entries.length}）`, tools);
      if (info.origin) {
        const o = h("div", "nav-origin");
        o.append(h("span", "nav-dim", "起点のノート: "), button(info.origin.title, () => ctx.open(info.origin.rel), "nav-link"));
        s.appendChild(o);
      }
      if (info.entries.length) s.appendChild(entryList(ctx, info.entries));
      else s.appendChild(h("div", "nav-dim", "まだ項目がありません。「＋ 新しいノート」で最初の項目を作れます。"));
    }
    // 載っている索引
    if (!info.is_index) {
      const s = section(`載っている索引（${info.indexed.length}）`, button("＋ 載せる", () => act.addToIndex(info), "nav-btn", "このノートを索引に載せる（\\l の g と同じ。よみの順に並ぶ）"));
      if (!info.indexed.length) s.appendChild(h("div", "nav-dim", "どの索引にも載っていません"));
      for (const x of info.indexed) {
        const li = h("div", "nav-indexed");
        li.append(button(x.index.rel === "index.md" ? "Global Index" : x.index.title, () => ctx.open(x.index.rel), "nav-link", x.path), h("span", "nav-sep", "›"), h("span", "nav-kw", x.label));
        if (x.path && x.index.rel !== "index.md") li.appendChild(h("div", "nav-dim small", x.path));
        s.appendChild(li);
      }
    }
    // トピック索引（BranchGroup）
    if (!info.entries || info.topics.length) {
      const s = section(`トピック索引（${info.topics.length}）`, info.entries ? null : button("＋ 作る", () => act.newTopic(info), "nav-btn", "このノートから分岐するトピック索引を作る（zk → n と同じ）"));
      if (!info.topics.length) s.appendChild(h("div", "nav-dim", "このノートが育ったら、トピック索引を作って細かい名前で索引できます"));
      for (const t of info.topics) {
        const th = h("div", "nav-subhead");
        th.append(button("▤ " + t.title, () => ctx.open(t.rel), "nav-label", "トピック索引を開く"), h("span", "nav-count", String(t.entries.length)));
        s.appendChild(th);
        if (t.entries.length) s.appendChild(entryList(ctx, t.entries));
      }
    }
    if (info.context && info.context.length) {
      const s = section("文脈（Context）");
      for (const c of info.context) s.appendChild(button(c.title, () => ctx.open(c.rel), "nav-link block"));
    }
  }

  async function drawSearch(qs) {
    body.textContent = "";
    const r = await ctx.query("nav.search", { q: qs });
    if (search.value.trim() !== qs) return;
    const res = r.ok ? r.result : [];
    if (!res.length) { body.appendChild(h("div", "nav-empty", "見つかりません")); return; }
    const s = h("section", "nav-sec");
    for (const x of res) {
      const li = h("button", "nav-hit"); li.type = "button";
      li.appendChild(h("span", "nav-kw", x.label));
      if (x.kind === "entry") li.appendChild(h("span", "nav-hitpath", (x.path || x.index.title) + " ›"));
      else li.appendChild(h("span", "nav-hitpath", "題" + (x.path ? "・" + x.path : "")));
      if (x.target.title !== x.label) li.appendChild(h("span", "nav-title", "→ " + x.target.title));
      li.addEventListener("click", () => ctx.open(x.target.rel));
      s.appendChild(li);
    }
    body.appendChild(s);
  }
  search.addEventListener("input", () => {
    clearTimeout(timer);
    const qs = search.value.trim();
    timer = setTimeout(() => { if (qs) drawSearch(qs); else draw(); }, 140);
  });
  search.addEventListener("keydown", (e) => {
    if (imeActive(e)) return;
    if (e.key === "Escape") { search.value = ""; draw(); ctx.focusVim && ctx.focusVim(); }
    if (e.key === "Enter") { const first = body.querySelector(".nav-hit"); if (first) first.click(); }
  });

  async function load(f, force) {
    if (!f) { info = null; file = ""; draw(); return; }
    if (f === file && !force) return;
    file = f;
    const my = ++busy;
    const r = await ctx.query("nav.note", { file: f });
    if (my !== busy) return;
    info = r.ok ? r.result : { missing: true };
    if (!search.value.trim()) draw();
  }
  draw();
  return {
    follow: (f) => load(f, false),
    refresh: () => load(file, true),
    info: () => info,
    focusSearch: () => { search.focus(); search.select(); },
    actions: act,
  };
}

// ---------------------------------------------------------------- 索引ブラウザ（列で辿る。Global Index → ノート → トピック索引 → …）
export function createIndexBrowser(ctx) {
  const el = h("div", "viewbox dibox keepfocus");
  const top = h("div", "di-top");
  const crumbs = h("div", "di-crumbs");
  const search = h("input", "nav-search"); search.type = "search"; search.placeholder = "索引語で探して、その場所へ"; search.setAttribute("aria-label", "索引語で探す");
  const hits = h("div", "di-hits"); hits.hidden = true;
  const unBtn = button("索引に無いノート", () => showUnindexed(), "nav-btn", "Global Index から辿れないノート（日記などは除く）。ここから索引に載せられます");
  top.append(crumbs, unBtn, search);
  const cols = h("div", "di-cols");
  const prev = h("div", "di-preview");
  const main = h("div", "di-main"); main.append(cols, prev);
  el.append(top, hits, main);
  // stack: 選んだ道。各段 { rel, label }。列 i には stack[i] のノートの「子の項目」（索引なら本文の項目、ノートならトピック索引の項目）を出す
  let stack = [];
  let focusCol = 0;

  async function itemsFor(rel) {
    const r = await ctx.query("nav.note", { file: rel });
    if (!r.ok) return { info: null, items: [] };
    const info = r.result;
    let items = [];
    if (info.entries) items = info.entries.map((e) => ({ ...e }));
    for (const t of info.topics || []) items.push({ head: t.title, rel: t.rel }, ...t.entries.map((e) => ({ ...e, viaTopic: t.rel })));
    return { info, items };
  }

  async function render() {
    cols.textContent = "";
    const crumbSteps = stack.map((s, i) => ({ rel: s.rel, label: i === 0 ? "Index" : s.label, title: s.label }));
    crumbs.textContent = "";
    crumbSteps.forEach((s, i) => { if (i) crumbs.appendChild(h("span", "nav-sep", "›")); crumbs.appendChild(button(s.label, () => { stack = stack.slice(0, i + 1); render(); }, "nav-crumb")); });
    for (let i = 0; i < stack.length; i++) {
      const col = h("div", "di-col" + (i === focusCol ? " focus" : ""));
      col.tabIndex = 0;
      cols.appendChild(col);
      const { info, items } = await itemsFor(stack[i].rel);
      if (!info) { col.appendChild(h("div", "nav-dim", "読めません")); continue; }
      const ch = h("div", "di-colhead");
      ch.append(button(i === 0 ? "Global Index" : info.title, () => ctx.open(info.rel), "nav-label", "Vim で開く"));
      if (KIND_BADGE[info.kind]) ch.appendChild(h("span", "nav-kind kind-" + info.kind, KIND_BADGE[info.kind]));
      col.appendChild(ch);
      if (!items.length) {
        col.appendChild(h("div", "nav-dim", info.entries ? "項目はまだありません" : "トピック索引はまだありません"));
        const act = navActions(ctx);
        col.appendChild(info.entries ? button("＋ 新しいノート", () => act.newInIndex(info), "nav-btn") : button("＋ トピック索引を作る", () => act.newTopic(info), "nav-btn"));
      }
      let lastRow = null;
      for (const it of items) {
        if (it.head) { col.appendChild(button("▤ " + it.head, () => ctx.open(it.rel), "di-topichead", "トピック索引を Vim で開く")); lastRow = null; continue; }
        if (it.row && it.row !== lastRow) { col.appendChild(h("div", "nav-rowhead", it.row)); lastRow = it.row; }
        const sel = stack[i + 1] && stack[i + 1].rel === it.rel && stack[i + 1].label === it.label;
        const b = h("button", "di-item" + (sel ? " sel" : "") + (it.missing ? " missing" : "")); b.type = "button";
        b.appendChild(h("span", "nav-kw", it.label));
        if (it.title && it.title !== it.label) b.appendChild(h("span", "nav-title", it.title));
        if ((it.topics || 0) > 0 || it.entries) b.appendChild(h("span", "di-more", "›"));
        b.title = "クリックで奥へ・ダブルクリックで Vim で開く";
        b.addEventListener("click", () => { stack = stack.slice(0, i + 1).concat([{ rel: it.rel, label: it.label }]); focusCol = i + 1; render(); showPreview(it.rel); });
        b.addEventListener("dblclick", () => ctx.open(it.rel));
        draggable(b, it.rel);
        col.appendChild(b);
      }
    }
    const last = cols.lastChild; if (last) last.scrollIntoView({ inline: "end", block: "nearest" });
  }

  async function showPreview(rel) {
    prev.textContent = "";
    const r = await ctx.query("nav.note", { file: rel });
    if (!r.ok) return;
    const i = r.result;
    prev.appendChild(h("div", "di-ptitle", i.title));
    const body = await noteBody(ctx, rel);
    if (body || i.preview) prev.appendChild(h("div", "di-ptext", body || i.preview));
    const bar = h("div", "di-pbar");
    const act = navActions(ctx);
    bar.append(button("Vim で開く", () => ctx.open(i.rel), "nav-btn primary"));
    if (!i.entries) bar.append(button("＋ トピック索引", () => act.newTopic(i), "nav-btn"), button("＋ 索引に載せる", () => act.addToIndex(i), "nav-btn"));
    else bar.append(button("＋ 新しいノート", () => act.newInIndex(i), "nav-btn"));
    prev.appendChild(bar);
    if (i.indexed && i.indexed.length) {
      prev.appendChild(h("div", "nav-sectitle", "載っている索引"));
      for (const x of i.indexed) prev.appendChild(h("div", "nav-dim", `${x.path ? x.path + " › " : ""}${x.label}`));
    }
  }

  // 索引に無いノート: 一覧から「載せる」
  async function showUnindexed() {
    hits.textContent = ""; hits.hidden = false;
    const r = await ctx.query("nav.unindexed", {});
    const list = r.ok ? r.result : [];
    const head = h("div", "di-hitshead");
    head.append(h("span", "", `索引から辿れないノート（${list.length}）`), button("閉じる", () => { hits.hidden = true; }, "nav-btn"));
    hits.appendChild(head);
    if (!list.length) hits.appendChild(h("div", "nav-dim", "全部のノートが Global Index から辿れます"));
    const act = navActions(ctx);
    for (const x of list) {
      const row = h("div", "di-unrow");
      const lab = button(x.title, () => ctx.open(x.rel), "nav-label", "Vim で開く");
      row.append(lab, h("span", "nav-title", [KIND_BADGE[x.kind] || "", x.time ? x.time.slice(0, 10) : "", x.preview || ""].filter(Boolean).join(" · ")),
        button("＋ 載せる", async () => { if (await act.addToIndex({ ...x, indexed: [] })) setTimeout(showUnindexed, 600); }, "nav-btn"));
      draggable(row, x.rel);
      hits.appendChild(row);
    }
  }

  // 探した項目へ: その項目のノートの道（crumbs）をそのまま列にする
  let timer = null;
  search.addEventListener("input", () => {
    clearTimeout(timer);
    timer = setTimeout(async () => {
      const qs = search.value.trim();
      hits.textContent = ""; hits.hidden = !qs;
      if (!qs) return;
      const r = await ctx.query("nav.search", { q: qs });
      for (const x of (r.ok ? r.result : []).slice(0, 30)) {
        const b = h("button", "nav-hit"); b.type = "button";
        b.append(h("span", "nav-kw", x.label), h("span", "nav-hitpath", x.kind === "entry" ? (x.path || x.index.title) + " ›" : "題"));
        b.addEventListener("click", () => jumpTo(x.target.rel));
        hits.appendChild(b);
      }
    }, 140);
  });
  async function jumpTo(rel) {
    hits.hidden = true; search.value = "";
    const r = await ctx.query("nav.note", { file: rel });
    const c = r.ok && r.result.crumbs && r.result.crumbs[0];
    if (!c) { toast("索引からは辿れないノートです（Vim で開きます）"); ctx.open(rel); return; }
    stack = c.filter((s) => s.via !== "topic").map((s, i) => ({ rel: s.rel, label: i === 0 ? "Index" : s.label || s.title }));
    focusCol = stack.length - 1;
    await render();
    showPreview(rel);
  }

  // キー: ←→ で列、↑↓ で項目、Enter で Vim で開く
  el.addEventListener("keydown", (e) => {
    if (e.target === search) return;
    const col = cols.children[focusCol];
    if (!col) return;
    const items = [...col.querySelectorAll(".di-item")];
    const cur = items.findIndex((b) => b === document.activeElement);
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      const n = items[Math.max(0, Math.min(items.length - 1, cur + (e.key === "ArrowDown" ? 1 : -1)))];
      if (n) { n.focus(); n.click(); }
    } else if (e.key === "ArrowLeft" && focusCol > 0) {
      e.preventDefault(); focusCol--; stack = stack.slice(0, focusCol + 2); render().then(() => cols.children[focusCol]?.querySelector(".di-item.sel")?.focus());
    } else if (e.key === "ArrowRight") {
      e.preventDefault(); const nx = cols.children[focusCol + 1]?.querySelector(".di-item"); if (nx) { focusCol++; nx.focus(); nx.click(); }
    } else if (e.key === "Enter" && cur >= 0) {
      e.preventDefault(); const s = stack[focusCol + 1]; if (s) ctx.open(s.rel);
    }
  });

  async function start() {
    const r = await ctx.query("nav.root", {});
    if (!r.ok || !r.result.rel) { cols.appendChild(h("div", "nav-empty", "Global Index（index.md）が見つかりません")); return; }
    stack = [{ rel: r.result.rel, label: "Index" }];
    focusCol = 0;
    render();
  }
  start();
  return { el, loaded: true, refresh: () => render(), jumpTo };
}
