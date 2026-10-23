// 紙のスキャンの番号付け（`\F`）。大きく・シンプルに・キーボードだけ。
//   画像を大きく出し、番号を入れて Enter → 次の番号なしの画像へ。
//   ↑ ↓ 前後 / d 日記として登録（日付を入れる）/ t トピック（起点の番号 → トピック名）/ Tab 前の番号を入れる / Esc 終了
// すでにある番号の一覧は出さない。出すのは、前に入れた番号だけ。
export function createScan(root, { api, onClose }) {
  root.className = "scan";
  root.innerHTML = `
    <div class="scan-count"></div>
    <div class="scan-img"><img alt=""><div class="scan-empty"></div></div>
    <div class="scan-prev"></div>
    <div class="scan-label"></div>
    <input class="scan-input" type="text" autocomplete="off" spellcheck="false" aria-label="">
    <div class="scan-msg"></div>
    <div class="scan-keys"></div>`;
  const $ = (s) => root.querySelector(s);
  const img = $(".scan-img img"), empty = $(".scan-empty"), input = $(".scan-input");
  const en = document.documentElement.lang === "en";
  const T = en ? {
    count: (i, n) => `${i} / ${n}`, none: "No unnumbered scans.", prev: (p) => `Previous: ${p}`, id: "Number", date: "Date written (YYYY-MM-DD)",
    topicId: "Number the topic starts from", topicName: "Topic name", busy: "Working…",
    keys: "Enter: set and go next   ↑ ↓: back / forth   d: paper diary   t: topic   Tab: put the previous number   Esc: finish",
    done: (id) => `Saved as ${id}`, bad: (e) => e,
  } : {
    count: (i, n) => `${i} / ${n}`, none: "番号のないスキャンはありません。", prev: (p) => `前: ${p}`, id: "番号", date: "日記が書かれた日（YYYY-MM-DD）",
    topicId: "トピックの起点の番号", topicName: "トピック名", busy: "整理しています…",
    keys: "Enter 決めて次へ　↑ ↓ 前後　d 日記　t トピック　Tab 前の番号を入れる　Esc 終了",
    done: (id) => `${id} にしました`, bad: (e) => e,
  };
  let scans = [], idx = 0, last = "", mode = "id", pendingTopicId = "", changed = 0, busy = false, url = "";

  const label = () => ({ id: T.id, date: T.date, topicId: T.topicId, topicName: T.topicName }[mode]);
  async function show() {
    const n = scans.length;
    $(".scan-count").textContent = n ? T.count(idx + 1, n) : "";
    $(".scan-prev").textContent = last ? T.prev(last) : "";
    $(".scan-label").textContent = n ? label() : "";
    input.hidden = !n;
    $(".scan-img").classList.toggle("none", !n);
    empty.textContent = n ? "" : T.none;
    $(".scan-keys").textContent = T.keys;
    if (url) { URL.revokeObjectURL(url); url = ""; }
    if (!n) { img.removeAttribute("src"); img.hidden = true; return; }
    img.hidden = false;
    const bytes = await api.image(scans[idx]);
    if (bytes) { url = URL.createObjectURL(new Blob([bytes])); img.src = url; } else img.removeAttribute("src");
    input.focus();
  }
  const msg = (t, bad) => { const m = $(".scan-msg"); m.textContent = t || ""; m.classList.toggle("bad", !!bad); };
  const setMode = (m) => { mode = m; input.value = ""; msg(""); $(".scan-label").textContent = label(); };

  async function commit() {
    const v = input.value.trim();
    if (!v || busy || !scans.length) return;
    const name = scans[idx];
    if (mode === "topicId") { pendingTopicId = v; setMode("topicName"); return; }
    busy = true; msg(T.busy);
    let r;
    if (mode === "date") r = await api.run("diary", [name, v]);
    else if (mode === "topicName") r = await api.run("assign", [name, pendingTopicId, v]);
    else r = await api.run("assign", [name, v]);
    busy = false;
    if (!r.ok) { msg(T.bad(r.error || "error"), true); return; }
    changed++;
    if (mode === "id") last = r.display;
    msg(T.done(r.display || r.date || v));
    scans.splice(idx, 1);
    if (idx >= scans.length) idx = Math.max(0, scans.length - 1);
    setMode("id");
    await show();
  }

  async function close() {
    if (busy) return;
    if (changed) { busy = true; msg(T.busy); await api.run("finish", []); busy = false; }
    root.hidden = true;
    onClose(changed);
  }

  input.addEventListener("keydown", async (e) => {
    if (e.isComposing) return;
    const k = e.key;
    if (k === "Enter") { e.preventDefault(); await commit(); }
    else if (k === "Escape") { e.preventDefault(); if (mode !== "id") setMode("id"); else await close(); }
    else if (k === "ArrowUp" || k === "ArrowDown") {
      e.preventDefault();
      if (!scans.length) return;
      idx = (idx + (k === "ArrowDown" ? 1 : -1) + scans.length) % scans.length;
      setMode("id"); await show();
    } else if (k === "Tab") { e.preventDefault(); if (last && mode === "id") input.value = last; }
    // 番号は数字から始まるので、空のときの d / t は命令
    else if (!input.value && mode === "id" && !e.ctrlKey && !e.metaKey && !e.altKey && (k === "d" || k === "t")) { e.preventDefault(); setMode(k === "d" ? "date" : "topicId"); }
  });
  root.addEventListener("keydown", (e) => { if (e.key === "Escape" && !scans.length) { e.preventDefault(); close(); } });
  root.tabIndex = -1;

  return {
    async open() {
      root.hidden = false; changed = 0; idx = 0; mode = "id"; msg(T.busy);
      const r = await api.run("list", []);
      scans = r.ok ? r.scans : []; last = r.ok ? r.last || "" : "";
      input.value = ""; msg(r.ok ? "" : r.error, !r.ok);
      await show();
      (scans.length ? input : root).focus();
    },
    isOpen: () => !root.hidden,
  };
}
