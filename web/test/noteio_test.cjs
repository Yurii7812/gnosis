// electron/noteio.cjs の試験（node test/noteio_test.cjs）。一時フォルダだけを使う。
const fs = require("fs");
const os = require("os");
const path = require("path");
const assert = require("assert/strict");
const io = require("../electron/noteio.cjs");

const base = process.env.TMPDIR || path.join(os.homedir(), "Desktop", "test");
fs.mkdirSync(base, { recursive: true });
const tmp = fs.mkdtempSync(path.join(base, "noteio-"));
const root = path.join(tmp, "vault");
fs.mkdirSync(path.join(root, "sub"), { recursive: true });
fs.mkdirSync(path.join(root, ".trash"));
fs.writeFileSync(path.join(root, "a.md"), "# A\n\n本文\n");
fs.writeFileSync(path.join(root, "sub", "b.md"), "# B\n");
fs.writeFileSync(path.join(root, ".trash", "h.md"), "hidden");
fs.writeFileSync(path.join(tmp, "outside.md"), "OUTSIDE");
fs.symlinkSync(path.join(tmp, "outside.md"), path.join(root, "link.md"));
try {
  // --- 読む ---
  const a = io.readNote(root, path.join(root, "a.md"));
  assert.equal(a.text, "# A\n\n本文\n");
  assert.equal(a.hash, io.sha256(a.text));

  // --- 保存: 普通・変更なし・競合 ---
  let r = io.writeNote(root, path.join(root, "a.md"), "# A\n\n本文を直した\n", a.hash);
  assert.equal(r.ok, true);
  assert.equal(fs.readFileSync(path.join(root, "a.md"), "utf8"), "# A\n\n本文を直した\n");
  assert.equal(r.hash, io.sha256("# A\n\n本文を直した\n"));
  const mt = fs.statSync(path.join(root, "a.md")).mtimeMs;
  r = io.writeNote(root, path.join(root, "a.md"), "# A\n\n本文を直した\n", r.hash);
  assert.equal(r.unchanged, true);                                                   // 同じ内容は書かない
  assert.equal(fs.statSync(path.join(root, "a.md")).mtimeMs, mt);
  // 外部がファイルを書き換えた → 古い期待ハッシュでは保存しない
  fs.writeFileSync(path.join(root, "a.md"), "# A\n\n外部の変更\n");
  r = io.writeNote(root, path.join(root, "a.md"), "# A\n\n私の変更\n", a.hash);
  assert.equal(r.ok, false);
  assert.equal(r.conflict, true);
  assert.equal(r.disk.text, "# A\n\n外部の変更\n");
  assert.equal(fs.readFileSync(path.join(root, "a.md"), "utf8"), "# A\n\n外部の変更\n");   // 何も書いていない
  assert.deepEqual(fs.readdirSync(root).filter((n) => n.includes("gnosis-tmp")), []);     // 一時ファイルも残さない
  // 強制保存: ディスクの版は .state/conflicts に残る
  r = io.writeNote(root, path.join(root, "a.md"), "# A\n\n私の変更\n", a.hash, { force: true });
  assert.equal(r.ok, true);
  assert.equal(fs.readFileSync(path.join(root, "a.md"), "utf8"), "# A\n\n私の変更\n");
  assert.equal(fs.readFileSync(r.savedAside, "utf8"), "# A\n\n外部の変更\n");
  assert.ok(r.savedAside.includes(path.join(".state", "conflicts")));
  // 新規ファイル
  r = io.writeNote(root, path.join(root, "new.md"), "新規", io.sha256(""));
  assert.equal(r.ok, true);
  assert.equal(fs.readFileSync(path.join(root, "new.md"), "utf8"), "新規");

  // --- 安全 ---
  assert.throws(() => io.readNote(root, path.join(tmp, "outside.md")), /vault の外/);
  assert.throws(() => io.readNote(root, path.join(root, "link.md")), /vault の外/);          // 外を指すシンボリックリンクは読まない
  assert.throws(() => io.writeNote(root, path.join(root, "link.md"), "改ざん", io.sha256("OUTSIDE")), /vault の外/);   // 書かない
  assert.throws(() => io.writeNote(root, path.join(root, "..", "x.md"), "x", ""), /vault の外/);
  assert.throws(() => io.writeNote(root, path.join(root, "a.txt"), "x", ""), /Markdown/);
  assert.throws(() => io.readNote(root, path.join(root, ".trash", "h.md")), /ドット/);
  assert.equal(fs.readFileSync(path.join(tmp, "outside.md"), "utf8"), "OUTSIDE");        // 外のファイルは無変更

  // --- リンクの解決 ---
  const from = path.join(root, "a.md");
  assert.deepEqual(io.resolveLink(root, from, "sub/b.md"), { file: path.join(root, "sub", "b.md"), anchor: "" });
  assert.deepEqual(io.resolveLink(root, from, "b.md#見出し"), { file: path.join(root, "sub", "b.md"), anchor: "見出し" });   // 名前だけでも（一意なら）
  assert.deepEqual(io.resolveLink(root, from, "https://example.com/x"), { external: "https://example.com/x" });
  assert.deepEqual(io.resolveLink(root, from, "javascript:alert(1)"), { missing: true });
  assert.deepEqual(io.resolveLink(root, from, "nothing.md"), { missing: true, ambiguous: false });
  assert.deepEqual(io.resolveLink(root, from, "#sec"), { self: true, anchor: "sec" });
  fs.writeFileSync(path.join(root, "dup.md"), "1");
  fs.writeFileSync(path.join(root, "sub", "dup.md"), "2");
  assert.equal(io.resolveLink(root, path.join(root, "sub", "b.md"), "dup.md").file, path.join(root, "sub", "dup.md"));   // 同じ階層が先
  assert.equal(io.resolveLink(root, path.join(root, "sub", "b.md"), "../dup.md").file, path.join(root, "dup.md"));
  assert.equal(io.resolveLink(root, from, "dup.md").file, path.join(root, "dup.md"));
  fs.mkdirSync(path.join(root, "x"));
  fs.writeFileSync(path.join(root, "x", "same.md"), "a"); fs.writeFileSync(path.join(root, "sub", "same.md"), "b");
  assert.deepEqual(io.resolveLink(root, from, "same.md"), { missing: true, ambiguous: true });        // 曖昧なら開かない
  console.log("noteio OK");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
