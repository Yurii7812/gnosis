// 紙のスキャンの番号付け（`\F`）。大きく・シンプルに・キーボードだけ。
//   1. 場所を選ぶ: Enter = vault の外のフォルダ（パソコンの中の写真）/ v = vault の中（`\M` で取り込んだ、番号のないもの）/ p 紙の番号の印（PA → PA-1a2）を変える / q 閉じる
//   2. （外のとき）フォルダを選ぶ:
//        一覧の先頭に「このフォルダを使う」、その下に Desktop・前回使ったフォルダ、そのあと今いるフォルダの中のフォルダ。
//        数字キー 1〜9 でその行へすぐ移って開く / j k ↑ ↓ で選ぶ / Enter 開く / u このフォルダを使う / ← Backspace 上へ
//        / で検索（文字を打てるのは / を押したあとだけ。Esc で検索をやめる）/ Esc 前の画面へ / q 閉じる
//   3. 番号を付ける（Space を押す前は「見る」状態）:
//        ↓ j 前の番号の子 / → l 次の連番 / ← h 取り消し / ↑ k 前の番号を直す / n p 次・前の画像 / Space 番号を入力 / d 日記として登録 / t トピック / Tab 前の番号を入れて入力 / s 並べ替え / q 閉じる
//        入力の画面（Space・d・t で開く）は Esc で閉じる。\F の画面は閉じない。
//   4. 並べ替え（s）: ポップアップ。↑ ↓ で基準を選ぶと、実際のファイルの一覧がその場で並び替わる。Enter で決める / Esc で元に戻す。
// すでにある番号の一覧は出さない。出すのは、前に入れた番号だけ。
export function createScan(root, { api, onClose }) {
  root.className = "scan";
  root.innerHTML = `
    <div class="scan-stage scan-source" hidden>
      <div class="scan-title"></div>
      <div class="scan-choice c-out"></div>
      <div class="scan-choice c-in"></div>
      <div class="scan-prefix"><span class="sp-label"></span><b class="sp-value"></b><input class="sp-input" type="text" maxlength="4" autocomplete="off" spellcheck="false" hidden aria-label=""></div>
      <div class="scan-keys k-source"></div>
    </div>
    <div class="scan-stage scan-folder" hidden>
      <div class="scan-title"></div>
      <div class="scan-path"></div>
      <input class="scan-search" type="text" autocomplete="off" spellcheck="false" hidden aria-label="">
      <div class="scan-list"></div>
      <div class="scan-keys k-folder"></div>
    </div>
    <div class="scan-stage scan-number" hidden>
      <div class="scan-count"></div>
      <div class="scan-img"><img alt=""><div class="scan-empty"></div></div>
      <div class="scan-prev"></div>
      <div class="scan-label"></div>
      <input class="scan-input" type="text" autocomplete="off" spellcheck="false" aria-label="" hidden>
      <div class="scan-msg"></div>
      <div class="scan-keys k-number"></div>
    </div>
    <div class="scan-sort" hidden>
      <div class="ss-title"></div>
      <div class="ss-body"><div class="ss-opts"></div><div class="ss-files"></div></div>
      <div class="ss-keys"></div>
    </div>`;
  const $ = (s) => root.querySelector(s);
  const img = $(".scan-img img"), empty = $(".scan-empty"), input = $(".scan-input"), search = $(".scan-search");
  const en = document.documentElement.lang === "en";
  const T = en ? {
    count: (i, n) => `${i} / ${n}`, none: "No unnumbered scans. Press q to close.", prev: (p) => `Previous: ${p}`, id: "Number", date: "Date written (YYYY-MM-DD)",
    topicId: "Number the topic starts from", topicName: "Topic name", busy: "Working…",
    keys: "↓ j: child of the previous number   → l: next number   ← h: undo   ↑ k: edit the previous number   Space: type a number   d: paper diary   t: topic   s: sort   n p: next / previous scan   q: close",
    needFirst: "Type the first number with Space.", undone: (id) => `Undid ${id}`,
    keysInput: "Enter: set and go next   Esc: close this input   Tab: put the previous number",
    done: (id) => `Saved as ${id}`, bad: (e) => e,
    title: "Which scans do you want to number?", out: "Enter   A folder outside the vault (photos on this computer)", in: (n) => `v   Inside the vault (unnumbered scans taken in with \\M)  ${n} scans`,
    srcKeys: "Enter / v: choose   p: change the paper number prefix   q: close",
    prefixLabel: "Paper note number prefix (p to change):  ", prefixHint: "1-4 capital letters (e.g. PA → PA-1a2). Enter: set   Esc: cancel", prefixBad: "Use 1-4 capital letters.", prefixDone: (p) => `Paper numbers now start with ${p}-`, folderTitle: "Choose the folder with the scans", use: (n) => `▶ Use this folder (${n} photos)`, up: "↑ (go up)",
    folderKeys: "1-9: open that row   j k: choose   Enter: open   u: use this folder   ← Backspace: up   /: search   Esc: back   q: close",
    searchKeys: "Type to filter   ↑ ↓: choose   Enter: open   Esc: stop searching", searchLabel: "Search folders",
    moving: "Moving the photos…", emptyFolder: "There are no photos in that folder.",
    recentHead: "Suggestions (Desktop, folders used before)", dirsHead: "Folders here", desktop: "Desktop", usedBefore: "used before", found: "found by search",
    sortTitle: "Sort", sortKeys: "↑ ↓: choose how to sort (the files change right away)   Enter: decide   Esc: put it back",
    sorts: { "name-asc": "Name (A → Z, oldest shot first)", "name-desc": "Name (Z → A, newest shot first)", "mtime-asc": "Modified: oldest first", "mtime-desc": "Modified: newest first", "size-asc": "Size: smallest first", "size-desc": "Size: largest first" },
  } : {
    count: (i, n) => `${i} / ${n}`, none: "番号のないスキャンはありません。q で閉じます。", prev: (p) => `前: ${p}`, id: "番号", date: "日記が書かれた日（YYYY-MM-DD）",
    topicId: "トピックの起点の番号", topicName: "トピック名", busy: "整理しています…",
    keys: "↓ j 前の番号の子　→ l 次の連番　← h 取り消し　↑ k 前の番号を直す　Space 番号を入力　d 日記　t トピック　s 並べ替え　n p 次・前の画像　q 閉じる",
    needFirst: "最初の画像は Space で番号を入力してください。", undone: (id) => `${id} を取り消しました`,
    keysInput: "Enter 決めて次へ　Esc この入力を閉じる　Tab 前の番号を入れる",
    done: (id) => `${id} にしました`, bad: (e) => e,
    title: "どのスキャンに番号を付ける？", out: "Enter　vault の外のフォルダ（パソコンの中の写真）", in: (n) => `v　vault の中（\\M で取り込んだ、番号のないもの）　${n} 枚`,
    srcKeys: "Enter / v で選ぶ　p 紙の番号の印を変える　q 閉じる",
    prefixLabel: "紙のノートの番号の印（p で変える）：", prefixHint: "英大文字 1〜4 字（例: PA → PA-1a2）。Enter 決める　Esc やめる", prefixBad: "英大文字 1〜4 字にしてください。", prefixDone: (p) => `紙の番号は ${p}- から始まります`, folderTitle: "スキャンが入っているフォルダを選ぶ", use: (n) => `▶ このフォルダを使う（写真 ${n} 枚）`, up: "↑ 上のフォルダへ",
    folderKeys: "1〜9 その行を開く　j k 選ぶ　Enter 開く　u このフォルダを使う　← Backspace 上へ　/ 検索　Esc 戻る　q 閉じる",
    searchKeys: "文字で絞り込み　↑ ↓ 選ぶ　Enter 開く　Esc 検索をやめる", searchLabel: "フォルダを検索",
    moving: "写真を移しています…", emptyFolder: "そのフォルダに写真がありません。",
    recentHead: "候補（Desktop・前回使ったフォルダ）", dirsHead: "このフォルダの中", desktop: "Desktop", usedBefore: "前回使った", found: "検索で見つかった",
    sortTitle: "並べ替え", sortKeys: "↑ ↓ 並べ方を選ぶ（ファイルの並びがその場で変わる）　Enter 決める　Esc 元に戻す",
    sorts: { "name-asc": "名前 昇順（撮った順・古い順）", "name-desc": "名前 降順（新しい順）", "mtime-asc": "更新日時 古い順", "mtime-desc": "更新日時 新しい順", "size-asc": "大きさ 小さい順", "size-desc": "大きさ 大きい順" },
  };
  const SORT_ORDER = ["name-asc", "name-desc", "mtime-asc", "mtime-desc", "size-asc", "size-desc"];
  let stage = "source", scans = [], info = {}, idx = 0, last = "", mode = "id", pendingTopicId = "", changed = 0, busy = false, url = "";
  let dirInfo = null, sel = 0, inCount = 0, suggest = [], searching = false, found = [], sortKey = "name-asc", sortPop = null;
  let inputOpen = false, prefix = "PA", prefixOpen = false;
  const pInput = $(".sp-input");

  const show = (name) => {
    stage = name;
    for (const st of ["source", "folder", "number"]) $(".scan-" + st).hidden = st !== name;
    root.focus();
  };
  const msg = (t, bad) => { const m = $(".scan-msg"); m.textContent = t || ""; m.classList.toggle("bad", !!bad); };

  // ---- 1. 場所を選ぶ ----
  async function openSource() {
    const r = await api.run("list", []);
    scans = r.ok ? r.scans : []; info = r.ok ? r.info || {} : {}; last = r.ok ? r.last || "" : "";
    inCount = scans.length;
    $(".scan-source .scan-title").textContent = T.title;
    $(".c-out").textContent = T.out;
    $(".c-in").textContent = T.in(inCount);
    $(".c-in").classList.toggle("dim", !inCount);
    $(".k-source").textContent = T.srcKeys;
    prefix = r.ok && r.prefix ? r.prefix : prefix;
    $(".sp-label").textContent = T.prefixLabel;
    $(".sp-value").textContent = prefix + "_";
    show("source");
  }

  // 紙の番号の印（設定 paperIdPrefix）。変えると、紙のノートの番号が新しい印に付け直される
  function openPrefix() {
    prefixOpen = true; pInput.hidden = false; pInput.value = prefix; $(".sp-value").hidden = true;
    $(".k-source").textContent = T.prefixHint; pInput.focus(); pInput.select();
  }
  function closePrefix() {
    prefixOpen = false; pInput.hidden = true; $(".sp-value").hidden = false; $(".k-source").textContent = T.srcKeys; root.focus();
  }
  async function commitPrefix() {
    const v = pInput.value.trim().toUpperCase();
    if (!/^[A-Z]{1,4}$/.test(v)) { $(".k-source").textContent = T.prefixBad; return; }
    closePrefix();
    if (v === prefix) return;
    $(".k-source").textContent = T.busy;
    const r = await api.run("prefix", [v]);
    if (r.ok) { prefix = r.prefix; $(".sp-value").textContent = prefix + "_"; $(".k-source").textContent = T.prefixDone(prefix); }
    else $(".k-source").textContent = r.error || "";
  }
  pInput.addEventListener("keydown", async (e) => {
    if (e.isComposing) return;
    e.stopPropagation();
    if (e.key === "Enter") { e.preventDefault(); await commitPrefix(); }
    else if (e.key === "Escape") { e.preventDefault(); closePrefix(); }
  });

  // ---- 2. フォルダを選ぶ ----
  const lastDir = () => { try { return localStorage.getItem("scanDir") || ""; } catch { return ""; } };
  async function openFolder(dir) {
    const sug = await api.recent();
    const d = await api.ls(dir || (sug.desktop || lastDir() || ""));
    if (!d.ok) { dirInfo = null; return; }
    dirInfo = d; sel = 0; searching = false; found = []; search.hidden = true; search.value = "";
    // 候補: Desktop（いつも）と、前回使ったフォルダ（新しい順）。今いる所と同じものは出さない
    suggest = [];
    if (sug.desktop && sug.desktop !== d.dir) suggest.push({ dir: sug.desktop, tag: T.desktop });
    for (const r of sug.recent || []) if (r !== d.dir && r !== sug.desktop) suggest.push({ dir: r, tag: T.usedBefore });
    $(".scan-folder .scan-title").textContent = T.folderTitle;
    $(".k-folder").textContent = T.folderKeys;
    drawFolder();
    show("folder");
  }
  const base = (p) => p.replace(/\/+$/, "").split("/").pop() || p;
  // 一覧の行。数字キー 1〜9 は「番号のある行」（候補とフォルダ）に付く
  function folderRows() {
    const rows = [];
    if (searching) {
      const q = search.value.normalize("NFKC").toLowerCase();
      const has = (p) => base(p).normalize("NFKC").toLowerCase().includes(q) || p.normalize("NFKC").toLowerCase().includes(q);
      for (const s of suggest) if (!q || has(s.dir)) rows.push({ kind: "dir", path: s.dir, text: `📁 ${base(s.dir)}   ${s.dir}`, tag: s.tag });
      for (const n of dirInfo.dirs) { const p = join(dirInfo.dir, n); if (!q || has(p)) rows.push({ kind: "dir", path: p, text: `📁 ${n}` }); }
      for (const p of found) if (!rows.some((r) => r.path === p)) rows.push({ kind: "dir", path: p, text: `📁 ${base(p)}   ${p}`, tag: T.found });
      return rows;
    }
    rows.push({ kind: "use", text: T.use(dirInfo.images) });
    if (dirInfo.parent) rows.push({ kind: "up", text: T.up });
    if (suggest.length) rows.push({ kind: "head", text: T.recentHead });
    for (const s of suggest) rows.push({ kind: "dir", path: s.dir, text: `📁 ${base(s.dir)}   ${s.dir}`, tag: s.tag });
    if (dirInfo.dirs.length) rows.push({ kind: "head", text: T.dirsHead });
    for (const n of dirInfo.dirs) rows.push({ kind: "dir", path: join(dirInfo.dir, n), text: `📁 ${n}` });
    return rows;
  }
  const selectable = (rows) => rows.map((r, i) => (r.kind === "head" ? -1 : i)).filter((i) => i >= 0);
  function drawFolder() {
    $(".scan-path").textContent = dirInfo.dir;
    const list = $(".scan-list");
    list.textContent = "";
    const rows = folderRows();
    const sels = selectable(rows);
    if (!sels.includes(sel)) sel = sels[0] ?? 0;
    let num = 0;
    rows.forEach((r, i) => {
      const el = document.createElement("div");
      if (r.kind === "head") { el.className = "scan-head"; el.textContent = r.text; list.appendChild(el); return; }
      el.className = "scan-row" + (i === sel ? " sel" : "") + (r.kind === "use" ? " use" : "");
      let n = "";
      if (r.kind === "dir" && !searching && ++num <= 9) n = num + "  ";
      el.textContent = n + r.text + (r.tag ? `  （${r.tag}）` : "");
      el.dataset.i = String(i);
      list.appendChild(el);
    });
    list.querySelector(".scan-row.sel")?.scrollIntoView({ block: "nearest" });
  }
  const join = (a, b) => (a.endsWith("/") ? a : a + "/") + b;
  async function folderOpenRow(r) {
    if (!r) return;
    if (r.kind === "dir") return openFolder(r.path);
    if (r.kind === "up") return openFolder(dirInfo.parent);
    return useFolder();
  }
  async function useFolder() {
    if (!dirInfo.images) { $(".scan-path").textContent = T.emptyFolder; return; }
    // 使う: 写真を受け皿へ移して、番号付けへ。使ったフォルダは、次から候補の先頭に出す
    try { localStorage.setItem("scanDir", dirInfo.dir); } catch { /* ignore */ }
    await api.remember(dirInfo.dir);
    $(".scan-path").textContent = T.moving;
    const m = await api.run("importmove", [dirInfo.dir]);
    if (!m.ok) { $(".scan-path").textContent = m.error || "error"; return; }
    await startNumbering();
  }
  // 数字キー: 番号のある行（候補とフォルダ）の N 番目を開く
  async function folderNth(n) {
    const rows = folderRows();
    let c = 0;
    for (const r of rows) if (r.kind === "dir" && ++c === n) return folderOpenRow(r);
  }
  function moveSel(d) {
    const rows = folderRows();
    const s = selectable(rows);
    if (!s.length) return;
    const at = Math.max(0, s.indexOf(sel));
    sel = s[Math.max(0, Math.min(s.length - 1, at + d))];
    drawFolder();
  }
  // 検索（/ のあとだけ文字を打てる）
  async function startSearch() {
    searching = true; sel = 0; found = [];
    search.hidden = false; search.value = ""; search.placeholder = T.searchLabel;
    $(".k-folder").textContent = T.searchKeys;
    drawFolder();
    search.focus();
  }
  function stopSearch() {
    searching = false; found = []; search.hidden = true; search.value = ""; sel = 0;
    $(".k-folder").textContent = T.folderKeys;
    drawFolder();
    root.focus();
  }
  let findTimer = null;
  search.addEventListener("input", () => {
    drawFolder();
    clearTimeout(findTimer);
    const q = search.value;
    findTimer = setTimeout(async () => {
      if (!searching || q !== search.value || !q.trim()) return;
      found = await api.find(dirInfo.dir, q);
      drawFolder();
    }, 150);
  });
  search.addEventListener("keydown", async (e) => {
    if (e.isComposing) return;
    e.stopPropagation();
    const k = e.key;
    if (k === "Escape") { e.preventDefault(); stopSearch(); }
    else if (k === "ArrowDown") { e.preventDefault(); moveSel(1); }
    else if (k === "ArrowUp") { e.preventDefault(); moveSel(-1); }
    else if (k === "Enter") { e.preventDefault(); const r = folderRows()[sel]; if (r) { await folderOpenRow(r); } }
  });

  // ---- 3. 番号を付ける ----
  const label = () => ({ id: T.id, date: T.date, topicId: T.topicId, topicName: T.topicName }[mode]);
  function fileRows() { return scans.map((n, i) => ({ n, i })); }
  async function showScan() {
    const n = scans.length;
    $(".scan-count").textContent = n ? T.count(idx + 1, n) : "";
    $(".scan-prev").textContent = last ? T.prev(last) : "";
    $(".scan-label").textContent = n && inputOpen ? label() : "";
    input.hidden = !(n && inputOpen);
    $(".scan-img").classList.toggle("none", !n);
    empty.textContent = n ? "" : T.none;
    $(".k-number").textContent = inputOpen ? T.keysInput : T.keys;
    if (url) { URL.revokeObjectURL(url); url = ""; }
    if (!n) { img.removeAttribute("src"); img.hidden = true; root.focus(); return; }
    img.hidden = false;
    const bytes = await api.image(scans[idx]);
    if (bytes) { url = URL.createObjectURL(new Blob([bytes])); img.src = url; } else img.removeAttribute("src");
    if (inputOpen) input.focus(); else root.focus();
  }
  // 入力の画面を開く（Space = 番号 / d = 日記 / t = トピック）。Esc で閉じる
  function openInput(m, prefill) {
    if (!scans.length) return;
    inputOpen = true; mode = m; input.value = prefill || ""; msg("");
    input.hidden = false;
    $(".scan-label").textContent = label();
    $(".k-number").textContent = T.keysInput;
    input.focus();
  }
  function closeInput() {
    inputOpen = false; mode = "id"; input.value = ""; msg("");
    input.hidden = true;
    $(".scan-label").textContent = "";
    $(".k-number").textContent = T.keys;
    root.focus();
  }
  const setMode = (m) => { mode = m; input.value = ""; msg(""); $(".scan-label").textContent = label(); };
  async function startNumbering() {
    const r = await api.run("list", []);
    scans = r.ok ? r.scans : []; info = r.ok ? r.info || {} : {}; last = r.ok ? r.last || "" : "";
    idx = 0; mode = "id"; inputOpen = false; input.value = ""; msg(r.ok ? "" : r.error, !r.ok);
    sortKey = "name-asc";
    show("number");
    await showScan();
  }

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
    // 番号の入力は開いたまま次へ（Esc で閉じる）。日記・トピックのあとは番号の入力に戻る
    mode = "id"; input.value = "";
    if (!scans.length) inputOpen = false;
    await showScan();
  }

  // 矢印キー・hjkl で番号を付ける（番号の入力を開いていないとき）
  //   ↓ j … 直前の番号の子（1a → 1a1）  → l … 次の連番（1a → 1b）  ← h … 直前の番号付けを取り消して、その画像へ戻る
  //   ↑ k … 直前の番号を入力欄に出して直す
  async function step(dir) {
    if (busy || !scans.length) return;
    if (!last) { msg(T.needFirst, true); return; }
    busy = true; msg(T.busy);
    const r = await api.run("step", [scans[idx], dir]);
    busy = false;
    if (!r.ok) { msg(T.bad(r.error || "error"), true); return; }
    changed++; last = r.display;
    msg(T.done(r.display));
    scans.splice(idx, 1);
    if (idx >= scans.length) idx = Math.max(0, scans.length - 1);
    await showScan();
  }
  async function undoLast() {
    if (busy) return;
    busy = true; msg(T.busy);
    const r = await api.run("undo", []);
    if (!r.ok) { busy = false; msg(T.bad(r.error || "error"), true); return; }
    const l = await api.run("list", []);
    busy = false;
    if (l.ok) { scans = l.scans; info = l.info || {}; }
    last = r.last || "";
    idx = Math.max(0, scans.indexOf(r.name));
    changed++;   // 取り消しも vault を変えた。閉じるときに Index などを作り直す
    msg(T.undone(r.display));
    await showScan();
  }
  const browse = async (d) => { if (scans.length) { idx = (idx + d + scans.length) % scans.length; await showScan(); } };

  async function close() {
    if (busy) return;
    if (changed) { busy = true; msg(T.busy); await api.run("finish", []); busy = false; }
    root.hidden = true;
    onClose(changed);
  }

  // ---- 4. 並べ替え（s）----
  const cmp = (key) => {
    const [by, dir] = key.split("-");
    const sgn = dir === "desc" ? -1 : 1;
    return (a, b) => {
      let d = 0;
      if (by === "name") d = a < b ? -1 : a > b ? 1 : 0;
      else if (by === "mtime") d = ((info[a] || {}).mtime || 0) - ((info[b] || {}).mtime || 0);
      else d = ((info[a] || {}).size || 0) - ((info[b] || {}).size || 0);
      return (d || (a < b ? -1 : a > b ? 1 : 0)) * sgn;
    };
  };
  const fmtTime = (s) => { const d = new Date(s * 1000); const p = (n) => String(n).padStart(2, "0"); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`; };
  const fmtSize = (n) => (n >= 1048576 ? (n / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(n / 1024)) + " KB");
  function drawSort() {
    const pop = $(".scan-sort");
    $(".ss-title").textContent = T.sortTitle;
    $(".ss-keys").textContent = T.sortKeys;
    const opts = $(".ss-opts"); opts.textContent = "";
    SORT_ORDER.forEach((k) => {
      const el = document.createElement("div");
      el.className = "ss-opt" + (k === sortKey ? " sel" : "");
      el.textContent = T.sorts[k];
      opts.appendChild(el);
    });
    const files = $(".ss-files"); files.textContent = "";
    scans.forEach((n, i) => {
      const el = document.createElement("div");
      el.className = "ss-file" + (i === idx ? " cur" : "");
      const inf = info[n] || {};
      el.textContent = `${i + 1}  ${n}   ${inf.mtime ? fmtTime(inf.mtime) : ""}   ${inf.size ? fmtSize(inf.size) : ""}`;
      files.appendChild(el);
    });
    files.querySelector(".cur")?.scrollIntoView({ block: "nearest" });
    pop.hidden = false;
  }
  function applySort(key) {
    const cur = scans[idx];
    sortKey = key;
    scans.sort(cmp(key));
    idx = Math.max(0, scans.indexOf(cur));
    drawSort();
  }
  function openSort() {
    if (scans.length < 2) return;
    sortPop = { keys: scans.slice(), key: sortKey, cur: scans[idx] };
    applySort(sortKey);
  }
  async function closeSort(decide) {
    $(".scan-sort").hidden = true;
    if (!decide && sortPop) { scans = sortPop.keys; sortKey = sortPop.key; idx = Math.max(0, scans.indexOf(sortPop.cur)); }
    sortPop = null;
    await showScan();
  }

  input.addEventListener("keydown", async (e) => {
    if (e.isComposing) return;
    e.stopPropagation();
    const k = e.key;
    if (k === "Enter") { e.preventDefault(); await commit(); }
    else if (k === "Escape") { e.preventDefault(); if (mode !== "id" && inputOpen && mode !== "topicName") { closeInput(); } else { closeInput(); } await showScan(); }
    else if (k === "ArrowUp" || k === "ArrowDown") {
      e.preventDefault();
      if (!scans.length) return;
      idx = (idx + (k === "ArrowDown" ? 1 : -1) + scans.length) % scans.length;
      setMode("id"); await showScan();
    } else if (k === "Tab") { e.preventDefault(); if (last && mode === "id") input.value = last; }
  });

  // 場所の選択・フォルダ選び・番号を付ける「見る」状態・並べ替えの、ルート全体のキー
  root.addEventListener("keydown", async (e) => {
    if (e.target === input || e.target === search || e.target === pInput || e.isComposing) return;
    const k = e.key;
    if (!$(".scan-sort").hidden) {
      const at = SORT_ORDER.indexOf(sortKey);
      if (k === "ArrowDown" || k === "j") { e.preventDefault(); applySort(SORT_ORDER[Math.min(SORT_ORDER.length - 1, at + 1)]); }
      else if (k === "ArrowUp" || k === "k") { e.preventDefault(); applySort(SORT_ORDER[Math.max(0, at - 1)]); }
      else if (k === "Enter") { e.preventDefault(); await closeSort(true); }
      else if (k === "Escape") { e.preventDefault(); await closeSort(false); }
      return;
    }
    if (stage === "source") {
      if (k === "Enter") { e.preventDefault(); await openFolder(""); }
      else if (k === "v" || k === "V") { e.preventDefault(); if (inCount) await startNumbering(); }
      else if (k === "p" || k === "P") { e.preventDefault(); openPrefix(); }
      else if (k === "q") { e.preventDefault(); await close(); }
    } else if (stage === "folder") {
      // 検索中にキーが検索欄の外に来たとき（フォーカスが外れた）も、Esc は検索をやめるだけ。ほかのキーは検索欄へ
      if (searching) { if (k === "Escape") { e.preventDefault(); stopSearch(); } else if (k === "ArrowDown") { e.preventDefault(); moveSel(1); } else if (k === "ArrowUp") { e.preventDefault(); moveSel(-1); } return; }
      if (k === "ArrowDown" || k === "j") { e.preventDefault(); moveSel(1); }
      else if (k === "ArrowUp" || k === "k") { e.preventDefault(); moveSel(-1); }
      else if (/^[1-9]$/.test(k)) { e.preventDefault(); await folderNth(Number(k)); }
      else if (k === "Enter" || k === "ArrowRight" || k === "l") { e.preventDefault(); await folderOpenRow(folderRows()[sel]); }
      else if (k === "u") { e.preventDefault(); await useFolder(); }
      else if (k === "/") { e.preventDefault(); await startSearch(); }
      else if ((k === "ArrowLeft" || k === "Backspace" || k === "h") && dirInfo.parent) { e.preventDefault(); await openFolder(dirInfo.parent); }
      else if (k === "Escape") { e.preventDefault(); await openSource(); }
      else if (k === "q") { e.preventDefault(); await close(); }
    } else if (stage === "number") {
      // 入力を開いているあいだ（フォーカスが入力欄の外に来たとき）: Esc は入力だけ閉じる。q など他のキーは入力の文字なので何もしない
      if (inputOpen) { if (k === "Escape") { e.preventDefault(); closeInput(); await showScan(); } return; }
      if (k === "q") { e.preventDefault(); await close(); }
      else if (k === "ArrowLeft" || k === "h") { e.preventDefault(); await undoLast(); }
      else if (!scans.length) return;
      else if (k === "ArrowDown" || k === "j") { e.preventDefault(); await step("down"); }
      else if (k === "ArrowRight" || k === "l") { e.preventDefault(); await step("right"); }
      else if (k === "ArrowUp" || k === "k") { e.preventDefault(); openInput("id", last || ""); }
      else if (k === "n") { e.preventDefault(); await browse(1); }
      else if (k === "p") { e.preventDefault(); await browse(-1); }
      else if (k === " ") { e.preventDefault(); openInput("id", ""); }
      else if (k === "d") { e.preventDefault(); openInput("date", ""); }
      else if (k === "t") { e.preventDefault(); openInput("topicId", ""); }
      else if (k === "Tab") { e.preventDefault(); openInput("id", last || ""); }
      else if (k === "s") { e.preventDefault(); openSort(); }
    }
  });
  root.tabIndex = -1;

  return {
    async open() {
      root.hidden = false; changed = 0; idx = 0; mode = "id"; inputOpen = false;
      await openSource();
    },
    isOpen: () => !root.hidden,
  };
}
