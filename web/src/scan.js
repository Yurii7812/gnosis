// 紙のスキャンの番号付け（`\F`）。大きく・シンプルに・キーボードだけ。
//   1. まず場所を選ぶ: Enter = vault の外のフォルダ（パソコンの中の写真）/ v = vault の中（`\M` で取り込んだ、番号のないもの）
//   2. （外のとき）フォルダを辿る: ↑ ↓ で選び、Enter で開く / 「このフォルダを使う」で決める、← か Backspace で上へ、Esc で戻る
//   3. 番号を付ける: 画像を大きく出し、番号を打って Enter → 次の番号なしへ。
//      ↑ ↓ 前後 / d 日記として登録（日付を入れる）/ t トピック（起点の番号 → トピック名）/ Tab 前の番号を入れる / Esc 終了
// すでにある番号の一覧は出さない。出すのは、前に入れた番号だけ。
export function createScan(root, { api, onClose }) {
  root.className = "scan";
  root.innerHTML = `
    <div class="scan-stage scan-source" hidden>
      <div class="scan-title"></div>
      <div class="scan-choice c-out"></div>
      <div class="scan-choice c-in"></div>
      <div class="scan-keys k-source"></div>
    </div>
    <div class="scan-stage scan-folder" hidden>
      <div class="scan-title"></div>
      <div class="scan-path"></div>
      <div class="scan-list"></div>
      <div class="scan-keys k-folder"></div>
    </div>
    <div class="scan-stage scan-number" hidden>
      <div class="scan-count"></div>
      <div class="scan-img"><img alt=""><div class="scan-empty"></div></div>
      <div class="scan-prev"></div>
      <div class="scan-label"></div>
      <input class="scan-input" type="text" autocomplete="off" spellcheck="false" aria-label="">
      <div class="scan-msg"></div>
      <div class="scan-keys k-number"></div>
    </div>`;
  const $ = (s) => root.querySelector(s);
  const img = $(".scan-img img"), empty = $(".scan-empty"), input = $(".scan-input");
  const en = document.documentElement.lang === "en";
  const T = en ? {
    count: (i, n) => `${i} / ${n}`, none: "No unnumbered scans.", prev: (p) => `Previous: ${p}`, id: "Number", date: "Date written (YYYY-MM-DD)",
    topicId: "Number the topic starts from", topicName: "Topic name", busy: "Working…",
    keys: "Enter: set and go next   ↑ ↓: back / forth   d: paper diary   t: topic   Tab: put the previous number   Esc: finish",
    done: (id) => `Saved as ${id}`, bad: (e) => e,
    title: "Which scans do you want to number?", out: "Enter   A folder outside the vault (photos on this computer)", in: (n) => `v   Inside the vault (unnumbered scans taken in with \\M)  ${n} scans`,
    srcKeys: "Enter / v: choose   Esc: close", folderTitle: "Choose the folder with the scans", use: (n) => `▶ Use this folder (${n} photos)`, up: "↑ (go up)",
    folderKeys: "↑ ↓: choose   Enter: open / use   ← Backspace: up   Esc: back", moving: "Moving the photos…", emptyFolder: "There are no photos in that folder.",
  } : {
    count: (i, n) => `${i} / ${n}`, none: "番号のないスキャンはありません。", prev: (p) => `前: ${p}`, id: "番号", date: "日記が書かれた日（YYYY-MM-DD）",
    topicId: "トピックの起点の番号", topicName: "トピック名", busy: "整理しています…",
    keys: "Enter 決めて次へ　↑ ↓ 前後　d 日記　t トピック　Tab 前の番号を入れる　Esc 終了",
    done: (id) => `${id} にしました`, bad: (e) => e,
    title: "どのスキャンに番号を付ける？", out: "Enter　vault の外のフォルダ（パソコンの中の写真）", in: (n) => `v　vault の中（\\M で取り込んだ、番号のないもの）　${n} 枚`,
    srcKeys: "Enter / v で選ぶ　Esc 閉じる", folderTitle: "スキャンが入っているフォルダを選ぶ", use: (n) => `▶ このフォルダを使う（写真 ${n} 枚）`, up: "↑ 上のフォルダへ",
    folderKeys: "↑ ↓ 選ぶ　Enter 開く / 使う　← Backspace 上へ　Esc 戻る", moving: "写真を移しています…", emptyFolder: "そのフォルダに写真がありません。",
  };
  let stage = "source", scans = [], idx = 0, last = "", mode = "id", pendingTopicId = "", changed = 0, busy = false, url = "";
  let dirInfo = null, sel = 0, inCount = 0;

  const show = (name) => {
    stage = name;
    for (const st of ["source", "folder", "number"]) $(".scan-" + st).hidden = st !== name;
    if (name === "number") input.focus(); else root.focus();
  };
  const msg = (t, bad) => { const m = $(".scan-msg"); m.textContent = t || ""; m.classList.toggle("bad", !!bad); };

  // ---- 1. 場所を選ぶ ----
  async function openSource() {
    const r = await api.run("list", []);
    scans = r.ok ? r.scans : []; last = r.ok ? r.last || "" : "";
    inCount = scans.length;
    $(".scan-source .scan-title").textContent = T.title;
    $(".c-out").textContent = T.out;
    $(".c-in").textContent = T.in(inCount);
    $(".c-in").classList.toggle("dim", !inCount);
    $(".k-source").textContent = T.srcKeys;
    show("source");
  }

  // ---- 2. フォルダを辿る ----
  async function openFolder(dir) {
    const d = await api.ls(dir || localStorage.getItem("scanDir") || "");
    if (!d.ok) { dirInfo = null; return; }
    dirInfo = d; sel = 0;
    $(".scan-folder .scan-title").textContent = T.folderTitle;
    $(".k-folder").textContent = T.folderKeys;
    drawFolder();
    show("folder");
  }
  function folderRows() {
    const rows = [{ kind: "use", text: T.use(dirInfo.images) }];
    if (dirInfo.parent) rows.push({ kind: "up", text: T.up });
    for (const n of dirInfo.dirs) rows.push({ kind: "dir", name: n, text: "📁 " + n });
    return rows;
  }
  function drawFolder() {
    $(".scan-path").textContent = dirInfo.dir;
    const list = $(".scan-list");
    list.textContent = "";
    folderRows().forEach((r, i) => {
      const el = document.createElement("div");
      el.className = "scan-row" + (i === sel ? " sel" : "") + (r.kind === "use" ? " use" : "");
      el.textContent = r.text;
      list.appendChild(el);
    });
    list.children[sel]?.scrollIntoView({ block: "nearest" });
  }
  const join = (a, b) => (a.endsWith("/") ? a : a + "/") + b;
  async function folderEnter() {
    const r = folderRows()[sel];
    if (r.kind === "dir") return openFolder(join(dirInfo.dir, r.name));
    if (r.kind === "up") return openFolder(dirInfo.parent);
    if (!dirInfo.images) { $(".scan-path").textContent = T.emptyFolder; return; }
    // 使う: 写真を受け皿へ移して、番号付けへ
    localStorage.setItem("scanDir", dirInfo.dir);
    $(".scan-path").textContent = T.moving;
    const m = await api.run("importmove", [dirInfo.dir]);
    if (!m.ok) { $(".scan-path").textContent = m.error || "error"; return; }
    await startNumbering();
  }

  // ---- 3. 番号を付ける ----
  const label = () => ({ id: T.id, date: T.date, topicId: T.topicId, topicName: T.topicName }[mode]);
  async function showScan() {
    const n = scans.length;
    $(".scan-count").textContent = n ? T.count(idx + 1, n) : "";
    $(".scan-prev").textContent = last ? T.prev(last) : "";
    $(".scan-label").textContent = n ? label() : "";
    input.hidden = !n;
    $(".scan-img").classList.toggle("none", !n);
    empty.textContent = n ? "" : T.none;
    $(".k-number").textContent = T.keys;
    if (url) { URL.revokeObjectURL(url); url = ""; }
    if (!n) { img.removeAttribute("src"); img.hidden = true; root.focus(); return; }
    img.hidden = false;
    const bytes = await api.image(scans[idx]);
    if (bytes) { url = URL.createObjectURL(new Blob([bytes])); img.src = url; } else img.removeAttribute("src");
    input.focus();
  }
  const setMode = (m) => { mode = m; input.value = ""; msg(""); $(".scan-label").textContent = label(); };
  async function startNumbering() {
    const r = await api.run("list", []);
    scans = r.ok ? r.scans : []; last = r.ok ? r.last || "" : "";
    idx = 0; mode = "id"; input.value = ""; msg(r.ok ? "" : r.error, !r.ok);
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
    setMode("id");
    await showScan();
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
      setMode("id"); await showScan();
    } else if (k === "Tab") { e.preventDefault(); if (last && mode === "id") input.value = last; }
    // 番号は数字から始まるので、空のときの d / t は命令
    else if (!input.value && mode === "id" && !e.ctrlKey && !e.metaKey && !e.altKey && (k === "d" || k === "t")) { e.preventDefault(); setMode(k === "d" ? "date" : "topicId"); }
  });

  // 場所の選択・フォルダ選び・（番号がもう無いとき）の、ルート全体のキー
  root.addEventListener("keydown", async (e) => {
    if (e.target === input || e.isComposing) return;
    const k = e.key;
    if (stage === "source") {
      if (k === "Enter") { e.preventDefault(); await openFolder(""); }
      else if (k === "v" || k === "V") { e.preventDefault(); if (inCount) await startNumbering(); }
      else if (k === "Escape") { e.preventDefault(); await close(); }
    } else if (stage === "folder") {
      const n = folderRows().length;
      if (k === "ArrowDown") { e.preventDefault(); sel = Math.min(n - 1, sel + 1); drawFolder(); }
      else if (k === "ArrowUp") { e.preventDefault(); sel = Math.max(0, sel - 1); drawFolder(); }
      else if (k === "Enter" || k === "ArrowRight") { e.preventDefault(); await folderEnter(); }
      else if ((k === "ArrowLeft" || k === "Backspace") && dirInfo.parent) { e.preventDefault(); await openFolder(dirInfo.parent); }
      else if (k === "Escape") { e.preventDefault(); await openSource(); }
    } else if (stage === "number" && k === "Escape" && !scans.length) { e.preventDefault(); await close(); }
  });
  root.tabIndex = -1;

  return {
    async open() {
      root.hidden = false; changed = 0; idx = 0; mode = "id";
      await openSource();
    },
    isOpen: () => !root.hidden,
  };
}
