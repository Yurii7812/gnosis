// GUI 編集モードのノートの読み書き（main プロセス。Electron に依存しない純粋な Node の関数）。
//   - 読むときに内容のハッシュ（SHA-256）を返す。保存するときは「読んだときのハッシュ」を添える。
//   - ディスクのハッシュが違えば（Vim・スマホ取り込み・別ウィンドウが変えた）上書きせず競合を返す。
//   - 書き込みは一時ファイル + rename（途中で止まっても元のファイルは壊れない）。
//   - vault の外・.md 以外・ドット始まりのフォルダのファイルは扱わない。
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const sha256 = (text) => crypto.createHash("sha256").update(text, "utf8").digest("hex");

function inside(root, file) {
  const r = fs.realpathSync(root);
  let f = path.resolve(file);
  // 実体のパスで判定する（vault の中のシンボリックリンクが外のファイルを指していても通さない）。
  // まだ無い新規ファイルは、親フォルダの実体で判定する。
  try {
    f = fs.realpathSync(f);
  } catch {
    f = path.join(fs.realpathSync(path.dirname(f)), path.basename(f));
  }
  const rel = path.relative(r, f);
  if (rel === "" || rel.startsWith("..") || path.isAbsolute(rel)) throw new Error("vault の外のファイルは扱えません");
  if (!f.toLowerCase().endsWith(".md")) throw new Error("Markdown（.md）のノートだけ扱えます");
  if (rel.split(path.sep).some((p) => p.startsWith("."))) throw new Error("ドット始まりのフォルダ・ファイルは扱えません");
  return f;
}

function readNote(root, file) {
  const f = inside(root, file);
  const text = fs.readFileSync(f, "utf8");
  return { text, hash: sha256(text), mtimeMs: fs.statSync(f).mtimeMs };
}

function atomicWrite(f, text) {
  const tmp = f + ".gnosis-tmp-" + process.pid;
  let mode = 0o644;
  try { mode = fs.statSync(f).mode & 0o777; } catch { /* 新規 */ }
  fs.writeFileSync(tmp, text, { encoding: "utf8", mode });
  fs.renameSync(tmp, f);
}

// 競合したときに、失う側の内容を残す（<vault>/.state/conflicts/。Vim 側の gnosis#conflict と同じ場所）
function saveAside(root, file, text, tag) {
  const dir = path.join(root, ".state", "conflicts");
  fs.mkdirSync(dir, { recursive: true });
  const d = new Date();
  const p2 = (n) => String(n).padStart(2, "0");
  const stamp = `${d.getFullYear()}${p2(d.getMonth() + 1)}${p2(d.getDate())}-${p2(d.getHours())}${p2(d.getMinutes())}${p2(d.getSeconds())}`;
  let out = path.join(dir, `${stamp}-${tag}-${path.basename(file)}`);
  for (let i = 2; fs.existsSync(out); i++) out = path.join(dir, `${stamp}-${tag}-${i}-${path.basename(file)}`);
  fs.writeFileSync(out, text, "utf8");
  return out;
}

// 保存。{ok:true, hash} / {ok:false, conflict:true, disk:{text, hash}}。
// force: ディスクの版を捨てて自分の版を書く（捨てるディスクの版は .state/conflicts/ に残す）。
function writeNote(root, file, text, expectedHash, { force = false } = {}) {
  const f = inside(root, file);
  let cur = null;
  try { cur = fs.readFileSync(f, "utf8"); } catch { /* 新規 */ }
  if (cur !== null && sha256(cur) !== expectedHash) {
    if (!force) return { ok: false, conflict: true, disk: { text: cur, hash: sha256(cur) } };
    const saved = saveAside(root, f, cur, "disk");
    atomicWrite(f, text);
    return { ok: true, hash: sha256(text), savedAside: saved };
  }
  if (cur === text) return { ok: true, hash: sha256(text), unchanged: true };   // 変わっていなければ書かない（更新時刻を動かさない）
  atomicWrite(f, text);
  return { ok: true, hash: sha256(text) };
}

// リンク先の解決。{file} / {external:url} / {missing:true}。相対パス → 無ければ vault の中でファイル名が一意なもの。
function resolveLink(root, fromFile, href) {
  const raw = String(href || "").trim().replace(/^<|>$/g, "").split(" ")[0];
  if (/^[a-z][a-z0-9+.-]*:/i.test(raw)) return /^(https?:|mailto:)/i.test(raw) ? { external: raw } : { missing: true };
  const target = decodeURIComponent(raw.split("#")[0]);
  if (!target) return { self: true, anchor: raw.split("#")[1] || "" };
  const anchor = raw.includes("#") ? raw.split("#").slice(1).join("#") : "";
  const cand = path.resolve(path.dirname(fromFile), target);
  try { if (fs.statSync(cand).isFile()) return { file: inside(root, cand), anchor }; } catch { /* 次へ */ }
  const want = path.basename(target).toLowerCase();
  const hits = [];
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.name.startsWith(".")) continue;
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.toLowerCase() === want || e.name.toLowerCase() === want + ".md") hits.push(p);
    }
  };
  walk(root);
  return hits.length === 1 ? { file: hits[0], anchor } : { missing: true, ambiguous: hits.length > 1 };
}

module.exports = { sha256, readNote, writeNote, saveAside, resolveLink, inside };
