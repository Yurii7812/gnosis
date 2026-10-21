// GUI 編集モード（アプリの編集モード）。Vim を知らなくても普通のエディタとして書ける。
//   Real Vim ⇄ GUI 編集 ⇄ 閲覧専用 は同じウィンドウで選ぶ排他のモード（同時に 2 つの編集主体は動かない）。
//   モードを切り替えるときは「保存して、新しいモードが読み直す」。
//   保存は、本文を Vim のバッファに渡して Vim が普通に :write する（保存時の処理が全部走る）。
//   保存の前にディスクの内容ハッシュを照合し、外（別の Vim・スマホ取り込み）が変えていたら上書きせず競合を見せる。
//   全部の操作にボタンとキーの両方の道があり、同じコマンド ID を呼ぶ。
import * as E from "./editcmds.js";
import { createHistory } from "./history.js";

const SAVE_DELAY = 1000;

export function createGuiEdit({ view, gui, $, getLast, showError, onChange }) {
  let on = false;
  let file = "";
  let hash = "";
  let dirty = false;      // 画面の内容がディスクと違う（まだ確定していない）
  let saving = false;
  let again = false;
  let timer = null;
  let paused = false;     // 競合の確認待ち（自動保存を止める）
  let loading = false;
  const hist = createHistory();

  const sel = () => view.selection();
  const doc = () => view.getText();

  function status() {
    const el = $("save-state");
    if (el) {
      el.textContent = !on ? "" : paused ? "競合: 確認してください" : saving ? "保存中…" : dirty ? "未保存" : "保存済み";
      el.className = "save-state" + (paused ? " conflict" : dirty ? " dirty" : "");
    }
    const d = $("dirty");
    if (d && on) d.textContent = dirty ? "●" : "";
    for (const b of document.querySelectorAll("#edit-tools [data-cmd='undo']")) b.disabled = !hist.canUndo();
    for (const b of document.querySelectorAll("#edit-tools [data-cmd='redo']")) b.disabled = !hist.canRedo();
    onChange?.(on);
  }

  // ---- 読み込み・保存 ----
  async function load(f) {
    loading = true;
    try {
      const r = await gui.readNote(f);
      if (!r.ok) throw new Error(r.error || "読み込めません");
      file = f; hash = r.hash; dirty = false; paused = false;
      view.setText(r.text);
      hist.reset();
    } finally { loading = false; status(); }
  }

  function schedule() {
    clearTimeout(timer);
    if (paused) return;
    timer = setTimeout(() => { if (view.isComposing()) schedule(); else save(); }, SAVE_DELAY);   // 日本語の変換中は待つ（未確定の文字を保存しない）
  }

  // 確定する。競合なら見せる。戻り値: 確定できた（または変更なし）なら true
  async function save({ force = false } = {}) {
    clearTimeout(timer);
    if (!on || !file) return true;
    if (saving) { again = true; return false; }
    if (!dirty && !force) return true;
    saving = true; status();
    const text = doc();
    let ok = false;
    try {
      const r = await gui.commitNote(file, text, hash, force);
      if (r.ok) {
        hash = r.hash; paused = false; ok = true;
        // 書いている間に打った分があるか。無ければ、保存時の処理で変わった内容を取り込む（記号の除去など）
        dirty = doc() !== text;
        // 変換中に本文を差し替えると変換が壊れるので、確定してから取り込む（dirty のまま次の保存で）
        if (!dirty && typeof r.text === "string" && r.text !== text) { if (view.isComposing()) dirty = true; else view.setText(r.text); }
        hideConflict();
      } else if (r.conflict) {
        paused = true;
        showConflict(r.disk);
      } else {
        showError(r.error || "保存できませんでした");
      }
    } catch (e) { showError(e && e.message || e); }
    saving = false;
    status();
    if ((again || dirty) && ok && !paused) { again = false; schedule(); }
    return ok;
  }

  // ---- 競合（別のものがファイルを変えていた） ----
  function hideConflict() { const c = $("conflict"); if (c) c.hidden = true; }
  function showConflict(disk) {
    const c = $("conflict");
    if (!c) return;
    c.hidden = false;
    c.querySelector(".msg").textContent = "このノートは、編集中に別のもの（別の Vim・スマホ取り込みなど）が書き換えました。どちらを残しますか？ どちらを選んでも、捨てる側は退避します。";
    c.querySelector("[data-act='mine']").onclick = async () => { hideConflict(); paused = false; await save({ force: true }); };
    c.querySelector("[data-act='theirs']").onclick = async () => {
      try {
        await gui.asideNote(file, doc());                       // 自分の版を退避
        loading = true; hash = disk.hash; view.setText(disk.text); hist.reset(); dirty = false; paused = false; loading = false;
      } catch (e) { showError(e && e.message || e); }
      hideConflict(); status();
    };
    c.querySelector("[data-act='later']").onclick = () => { hideConflict(); };      // 自動保存は止めたまま（保存ボタンで再び確認）
  }

  // ---- モードの入り切り ----
  async function enter() {
    if (on) return true;
    const last = getLast();
    if (!last.file || last.bt) { showError("このバッファは GUI 編集にできません（ノートを開いてください）"); return false; }
    const r = await gui.enterEdit();           // Vim の未保存の変更を保存させる
    if (!r.ok) { showError(r.error || "Vim の未保存の変更を保存できませんでした"); return false; }
    try { await load(r.file || last.file); } catch (e) { showError(e && e.message || e); return false; }
    on = true;
    view.setEditable(true);
    document.body.classList.add("gui-edit");
    view.focus();
    status();
    return true;
  }

  async function leave() {
    if (!on) return true;
    clearTimeout(timer);
    if (dirty && !(await save())) {            // 確定できない（競合など）まま Vim に戻らない
      showError("保存できていないので、GUI 編集のままにします");
      return false;
    }
    on = false;
    view.setEditable(false);
    document.body.classList.remove("gui-edit");
    hideConflict();
    await gui.leaveEdit();                     // 外で変わったファイルを Vim に読み直させる
    status();
    return true;
  }

  // ---- 外（Vim・同期）から ----
  // Vim のバッファが変わったとき（別のノートへ移った・保存時の同期で関係ブロックが変わった）
  async function onVimState(s) {
    if (!on || loading || saving) return;
    if (s.file && s.file !== file && !s.bt) {   // Vim が別のノートを開いた（リンクを開いた）
      if (dirty) await save();
      try { await load(s.file); } catch (e) { showError(e && e.message || e); }
      return;
    }
    if (s.lines && !dirty && !paused && !view.isComposing()) {
      const vimText = s.lines.join("\n");
      if (doc().replace(/\n$/, "") !== vimText) {       // 保存時の同期などで内容が変わった → ディスクの版を取り込む
        const r = await gui.readNote(file);
        if (r.ok && r.hash !== hash && !dirty) { hash = r.hash; view.setText(r.text); hist.reset(); status(); }
      }
    }
  }

  // ---- 編集 ----
  function onUserChange(u) {
    if (!on || loading) return;
    hist.record(() => u.startState.doc.toString());
    dirty = true;
    schedule();
    status();
  }

  function apply(result) { return view.applyEdit(result); }

  async function openLink(href) {
    const r = await gui.resolveLink(file, href);
    if (!r.ok) { showError(r.error || "リンクを解決できません"); return; }
    if (r.external) { showError("外部のリンクです: " + r.external); return; }
    if (r.self || !r.file) { if (r.missing) showError("リンク先のノートがありません: " + href); return; }
    if (dirty && !(await save())) return;
    const o = await gui.openNote(r.file);
    if (!o.ok) showError(o.error || "開けませんでした");
  }

  // 位置 pos のリンクを開く（描かれたリンクのクリック・Ctrl+クリック・「リンクを開く」）
  async function openAt(pos, href) { const h = href || view.linkAt(pos); if (h) await openLink(h); return !!h; }

  // ---- コマンド（ボタン・キー・メニューが同じ ID を呼ぶ） ----
  const ask = (label, initial = "") => new Promise((resolve) => {
    const box = $("ask");
    if (!box) return resolve(null);
    box.hidden = false;
    box.querySelector("label").textContent = label;
    const input = box.querySelector("input");
    input.value = initial;
    input.focus();
    const done = (v) => { box.hidden = true; input.onkeydown = null; box.querySelector("[data-act='ok']").onclick = null; box.querySelector("[data-act='cancel']").onclick = null; view.focus(); resolve(v); };
    input.onkeydown = (e) => { if (e.isComposing || e.keyCode === 229) return; if (e.key === "Enter") { e.preventDefault(); done(input.value); } else if (e.key === "Escape") { e.preventDefault(); done(null); } };
    box.querySelector("[data-act='ok']").onclick = () => done(input.value);
    box.querySelector("[data-act='cancel']").onclick = () => done(null);
  });

  const commands = {
    undo() {
      const prev = hist.undo(doc());
      if (prev == null) return false;
      view.replaceAll(prev); dirty = true; schedule(); status(); return true;
    },
    redo() {
      const next = hist.redo(doc());
      if (next == null) return false;
      view.replaceAll(next); dirty = true; schedule(); status(); return true;
    },
    async save() { return save({ force: false }); },
    bold: () => apply(E.toggleWrap(doc(), sel().from, sel().to, "**")),
    italic: () => apply(E.toggleWrap(doc(), sel().from, sel().to, "*")),
    strike: () => apply(E.toggleWrap(doc(), sel().from, sel().to, "~~")),
    code: () => apply(E.toggleWrap(doc(), sel().from, sel().to, "`")),
    h1: () => apply(E.setHeading(doc(), sel().head, 1)),
    h2: () => apply(E.setHeading(doc(), sel().head, 2)),
    h3: () => apply(E.setHeading(doc(), sel().head, 3)),
    bullet: () => apply(E.toggleLinePrefix(doc(), sel().from, sel().to, "bullet")),
    number: () => apply(E.toggleLinePrefix(doc(), sel().from, sel().to, "number")),
    task: () => apply(E.toggleLinePrefix(doc(), sel().from, sel().to, "task")),
    quote: () => apply(E.toggleLinePrefix(doc(), sel().from, sel().to, "quote")),
    checkbox: () => apply(E.toggleTaskAt(doc(), sel().head)),
    async link() {
      const s = sel();
      const url = await ask("リンク先（ノートのファイル名・URL）", "");
      if (url == null || !url.trim()) return false;
      return apply(E.makeLink(doc(), s.from, s.to, url.trim()));
    },
    async openLink() { return openAt(sel().head, ""); },
    enter() { return apply(E.enterInList(doc(), sel().head)) || false; },   // false を返すと CodeMirror が普通の改行をする
    indent() { return apply(E.indentLines(doc(), sel().from, sel().to, 1)) || false; },
    outdent() { return apply(E.indentLines(doc(), sel().from, sel().to, -1)) || false; },
  };

  function run(id) {
    const f = commands[id];
    if (!on || !f) return false;
    return f();
  }

  return { enter, leave, isOn: () => on, onVimState, onUserChange, openAt, run, commands, save, state: () => ({ on, file, hash, dirty, saving, paused }) };
}
