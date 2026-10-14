// Gnosis の状態と設定（Vim 側の autoload/gnosis/{home,vault,settings,theme}.vim と同じファイル・同じ規則）。
//
//   Gnosis ホーム（vault の外。Git 管理のソースには書かない）
//     vaults.json  … 登録済みの vault と最後に選んだ vault
//     themes/      … 追加したテーマ（GitHub のリポジトリを git clone したもの）
//     logs/        … アプリのログ
//   vault ごとの設定: <vault>/.gnosis/settings.json
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFile } = require("child_process");

const REPO = path.resolve(__dirname, "..", "..");

function gnosisHome() {
  if (process.env.GNOSIS_HOME) return path.resolve(process.env.GNOSIS_HOME);
  if (process.platform === "win32") return path.join(process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming"), "Gnosis");
  if (process.platform === "darwin") return path.join(os.homedir(), "Library", "Application Support", "Gnosis");
  return path.join(process.env.XDG_DATA_HOME || path.join(os.homedir(), ".local", "share"), "gnosis");
}

function readJson(file, dflt) {
  try {
    const v = JSON.parse(fs.readFileSync(file, "utf8"));
    return v && typeof v === "object" && !Array.isArray(dflt) === !Array.isArray(v) ? v : dflt;
  } catch { return dflt; }
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = file + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2) + "\n");
  fs.renameSync(tmp, file);
}

function normalize(p) {
  if (!p) return "";
  let r = path.resolve(p.replace(/^~(?=$|[\\/])/, os.homedir()));
  if (r.length > 1 && /[\\/]$/.test(r) && !/^[A-Za-z]:\\$/.test(r)) r = r.replace(/[\\/]+$/, "");
  return r;
}

function same(a, b) {
  const x = normalize(a), y = normalize(b);
  return process.platform === "win32" ? x.toLowerCase() === y.toLowerCase() : x === y;
}

const isDir = (p) => { try { return fs.statSync(p).isDirectory(); } catch { return false; } };

// ---------------------------------------------------------------- vault の登録簿

function registryFile() { return path.join(gnosisHome(), "vaults.json"); }

function legacyRootFile() { return path.join(os.homedir(), ".vim", "simple_yurii_note", "root.txt"); }

function fixRegistry(reg) {
  const out = { version: 1, last: typeof reg.last === "string" ? reg.last : "", vaults: [] };
  for (const v of Array.isArray(reg.vaults) ? reg.vaults : []) {
    if (v && typeof v.path === "string" && v.path) out.vaults.push({ path: v.path, name: v.name || path.basename(v.path) });
  }
  if (reg.imported_from) out.imported_from = reg.imported_from;
  return out;
}

// 読む。無ければ旧 simple-yurii-note の root.txt を 1 回だけ取り込む（root.txt は消さない）。
function loadRegistry() {
  const file = registryFile();
  if (!fs.existsSync(file)) {
    const reg = { version: 1, last: "", vaults: [] };
    try {
      const legacy = legacyRootFile();
      const root = fs.readFileSync(legacy, "utf8").split(/\r?\n/)[0].trim();
      if (root) {
        let p = normalize(root);
        if (path.basename(p) === "note") p = path.dirname(p);
        reg.vaults.push({ path: p, name: path.basename(p) });
        reg.last = p;
        reg.imported_from = legacy;
        writeJson(file, reg);
      }
    } catch { /* 旧環境なし */ }
    return fixRegistry(reg);
  }
  return fixRegistry(readJson(file, {}));
}

function saveRegistry(reg) { writeJson(registryFile(), reg); }

function listVaults() {
  const reg = loadRegistry();
  return reg.vaults.map((v) => ({ path: v.path, name: v.name, exists: isDir(v.path), last: same(v.path, reg.last) }));
}

function lastVault() {
  const reg = loadRegistry();
  const v = reg.vaults.find((x) => same(x.path, reg.last));
  return v ? v.path : "";
}

// 既存のフォルダを登録する（無いフォルダは作らない）
function addVault(p, name) {
  let n = normalize(p);
  if (!n || !isDir(n)) throw new Error("vault.not_found:" + n);
  if (path.basename(n) === "note" && isDir(path.join(path.dirname(n), ".crypt"))) n = path.dirname(n);
  const reg = loadRegistry();
  const found = reg.vaults.find((v) => same(v.path, n));
  if (found) { if (name) found.name = name; } else reg.vaults.push({ path: n, name: name || path.basename(n) });
  saveRegistry(reg);
  return n;
}

// 新しい vault を作る（フォルダを作り、設定を書く。Index と操作ガイドは Vim が初回に作る）
function createVault(p, name, lang) {
  const n = normalize(p);
  if (!n) throw new Error("vault.path_empty:");
  if (fs.existsSync(n) && !isDir(n)) throw new Error("vault.not_dir:" + n);
  if (isDir(n) && fs.readdirSync(n).some((f) => f.endsWith(".md"))) throw new Error("vault.create_has_notes:" + n);
  fs.mkdirSync(n, { recursive: true });
  const s = defaultSettings();
  if (lang) s.language = lang;
  saveSettings(n, s);
  return addVault(n, name);
}

// 一覧から外す（ノート・フォルダは消さない）
function removeVault(p) {
  const reg = loadRegistry();
  const before = reg.vaults.length;
  reg.vaults = reg.vaults.filter((v) => !same(v.path, p));
  if (same(reg.last, p)) reg.last = "";
  saveRegistry(reg);
  return before !== reg.vaults.length;
}

function selectVault(p) {
  const n = normalize(p);
  if (!loadRegistry().vaults.find((v) => same(v.path, n))) addVault(n);
  const reg = loadRegistry();
  const v = reg.vaults.find((x) => same(x.path, n));
  reg.last = v ? v.path : n;
  saveRegistry(reg);
  return reg.last;
}

// vault のパス（A）からノートの root（A/note があれば A/note）
function noteRoot(p) {
  const n = normalize(p);
  if (path.basename(n) !== "note" && isDir(path.join(n, "note"))) return path.join(n, "note");
  return n;
}

// ---------------------------------------------------------------- vault ごとの設定

function systemLang() {
  for (const v of [process.env.LC_ALL, process.env.LC_MESSAGES, process.env.LANG]) {
    if (v && v !== "C" && v !== "POSIX") return /^ja/i.test(v) ? "ja" : "en";
  }
  try { return /^ja/i.test(Intl.DateTimeFormat().resolvedOptions().locale) ? "ja" : "en"; } catch { return "en"; }
}

function defaultSettings() {
  return {
    version: 1,
    language: systemLang(),
    window: { maximized: true, width: 1200, height: 860 },
    fontSize: 16,
    appearance: "light",
    theme: { kind: "builtin" },
    customThemes: {},
    // \A のアプリ（Electron）の配色。通常の Vim の配色（theme / customThemes）とは別の設定
    appTheme: { kind: "builtin" },
    appCustomThemes: {},
  };
}

const clamp = (v, lo, hi, d) => { const n = Math.round(Number(v)); return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d; };
const HEX = /^#[0-9a-fA-F]{6}$/;

function validateSettings(s) {
  const d = defaultSettings();
  const out = { ...d, ...(s && typeof s === "object" ? s : {}) };
  out.language = out.language === "en" || out.language === "ja" ? out.language : d.language;
  out.appearance = out.appearance === "dark" ? "dark" : "light";
  out.fontSize = clamp(out.fontSize, 8, 48, 16);
  const w = { ...d.window, ...(out.window && typeof out.window === "object" ? out.window : {}) };
  out.window = { maximized: !!w.maximized, width: clamp(w.width, 480, 10000, 1200), height: clamp(w.height, 360, 10000, 860) };
  const th = out.theme && typeof out.theme === "object" ? out.theme : {};
  out.theme = ["builtin", "custom", "plugin"].includes(th.kind) ? th : { kind: "builtin" };
  out.customThemes = cleanCustomThemes(out.customThemes);
  const at = out.appTheme && typeof out.appTheme === "object" ? out.appTheme : {};
  out.appTheme = at.kind === "custom" && typeof at.name === "string" ? { kind: "custom", name: at.name } : { kind: "builtin" };
  out.appCustomThemes = cleanCustomThemes(out.appCustomThemes);
  return out;
}

const COLOR_KEYS = ["bg", "fg", "link", "heading", "selection", "cursorline"];

function cleanCustomThemes(raw) {
  const ct = {};
  for (const [name, c] of Object.entries(raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {})) {
    if (!c || typeof c !== "object") continue;
    const base = c.base === "dark" || c.base === "light" ? c.base : HEX.test(c.bg || "") && luminance(c.bg) < 0.4 ? "dark" : "light";
    const e = { base };
    for (const k of COLOR_KEYS) if (HEX.test(c[k] || "")) e[k] = c[k].toLowerCase();
    ct[name] = e;
  }
  return ct;
}

function settingsFile(vault) { return path.join(normalize(vault), ".gnosis", "settings.json"); }

function loadSettings(vault) {
  if (!vault) return defaultSettings();
  return validateSettings(readJson(settingsFile(vault), {}));
}

function saveSettings(vault, s) {
  const v = validateSettings(s);
  writeJson(settingsFile(vault), v);
  return v;
}

// ---------------------------------------------------------------- テーマ

function builtinPalettes() {
  return readJson(path.join(REPO, "assets", "themes", "builtin.json"), {
    start: { base: "light", bg: "#ffffff", fg: "#000000", link: "#000000", heading: "#000000", selection: "#d0d0d0", cursorline: "#f2f2f2" },
    light: { base: "light", bg: "#ffffff", fg: "#1f2328", link: "#0969da", heading: "#0b3d91", selection: "#b6d6ff", cursorline: "#f2f5f8" },
    dark: { base: "dark", bg: "#0d1117", fg: "#e6edf3", link: "#4493f8", heading: "#ffa657", selection: "#264f78", cursorline: "#161b22" },
    app: { base: "light", bg: "#ffffff", fg: "#1f2328", link: "#0b57d0", heading: "#7c2d12", muted: "#57606a", accent: "#0969da", selection: "#b6d6ff", cursorline: "#f2f5f8" },
  });
}

// 組み込み・カスタムの色（追加テーマの色は Vim が読み込んだあと画面へ送る）
function paletteFor(s) {
  const pals = builtinPalettes();
  if (s.theme.kind === "custom" && s.customThemes[s.theme.name]) {
    const c = s.customThemes[s.theme.name];
    return { ...(pals[c.base] || pals.light), ...c };
  }
  return { ...(pals[s.appearance] || pals.light), base: s.appearance };
}

// \A のアプリの配色。既定は白（palettes.app）。自分で作ったものは、背景か本文を変えたら補助の色（muted / accent）を作り直す。
// 通常の Vim の配色（paletteFor）とは別。Vim 側の変更はここに影響しない（逆も同じ）。
function appPaletteFor(s) {
  const pals = builtinPalettes();
  const base = { ...(pals.app || pals.light) };
  const th = s.appTheme || { kind: "builtin" };
  const c = th.kind === "custom" && s.appCustomThemes ? s.appCustomThemes[th.name] : null;
  if (!c) return base;
  const p = { ...base };
  if (c.bg || c.fg) { delete p.muted; delete p.accent; }
  for (const k of COLOR_KEYS) if (HEX.test(c[k] || "")) p[k] = c[k];
  p.base = c.base === "dark" || c.base === "light" ? c.base : luminance(p.bg) < 0.4 ? "dark" : "light";
  return p;
}

function luminance(hex) {
  const ch = [1, 3, 5].map((i) => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2];
}

// `Plug 'owner/repo'` などから owner/repo を取り出す（Vim script としては実行しない）
function parseThemeSpec(spec) {
  let s = String(spec || "").trim();
  const m = s.match(/^Plug\s+(['"])([^'"]+)\1\s*(,.*)?$/);
  if (m) s = m[2];
  s = s.replace(/^(?:https?:\/\/)?(?:www\.)?github\.com\//, "").replace(/^git@github\.com:/, "").replace(/\.git$/, "").replace(/\/+$/, "");
  if (/^[A-Za-z0-9][A-Za-z0-9-]{0,38}\/[A-Za-z0-9._-]{1,100}$/.test(s) && !/\/\.\.?$/.test(s)) return s;
  return "";
}

function themeDir(repo) { return path.join(gnosisHome(), "themes", repo.replace("/", "__")); }

function installedThemes() {
  const dir = path.join(gnosisHome(), "themes");
  let names = [];
  try { names = fs.readdirSync(dir); } catch { return []; }
  return names.filter((n) => isDir(path.join(dir, n))).map((n) => {
    let cs = [];
    try { cs = fs.readdirSync(path.join(dir, n, "colors")).filter((f) => f.endsWith(".vim")).map((f) => f.slice(0, -4)).sort(); } catch { /* なし */ }
    return { repo: n.replace("__", "/"), colorschemes: cs };
  });
}

function installTheme(spec) {
  return new Promise((resolve) => {
    const repo = parseThemeSpec(spec);
    if (!repo) return resolve({ ok: false, repo: "", error: "theme.bad_spec", detail: String(spec) });
    const dir = themeDir(repo);
    const done = () => {
      let cs = [];
      try { cs = fs.readdirSync(path.join(dir, "colors")).filter((f) => f.endsWith(".vim")).map((f) => f.slice(0, -4)).sort(); } catch { /* なし */ }
      if (!cs.length) { fs.rmSync(dir, { recursive: true, force: true }); return resolve({ ok: false, repo, error: "theme.no_colors", detail: repo }); }
      resolve({ ok: true, repo, colorschemes: cs });
    };
    if (isDir(dir)) return done();
    fs.mkdirSync(path.dirname(dir), { recursive: true });
    execFile("git", ["clone", "--depth", "1", "--", `https://github.com/${repo}.git`, dir], { timeout: 120000 }, (err, _o, stderr) => {
      if (err) {
        fs.rmSync(dir, { recursive: true, force: true });
        return resolve({ ok: false, repo, error: err.code === "ENOENT" ? "theme.no_git" : "theme.clone_failed", detail: repo + ": " + String(stderr || err.message).trim() });
      }
      done();
    });
  });
}

// ---------------------------------------------------------------- 文言・アート

function catalog(lang) {
  const ja = readJson(path.join(REPO, "i18n", "ja.json"), {}).msg || {};
  const en = readJson(path.join(REPO, "i18n", "en.json"), {}).msg || {};
  return lang === "en" ? { ...ja, ...en } : ja;
}

function art() {
  const out = {};
  for (const w of [44, 60, 80]) {
    try { out[w] = fs.readFileSync(path.join(REPO, "assets", "chnoubis", `chnoubis-${w}.txt`), "utf8").replace(/\n+$/, "").split("\n"); } catch { /* なし */ }
  }
  return out;
}

module.exports = {
  REPO, gnosisHome, normalize, same, loadRegistry, listVaults, lastVault, addVault, createVault, removeVault, selectVault,
  noteRoot, defaultSettings, validateSettings, loadSettings, saveSettings, builtinPalettes, paletteFor, appPaletteFor, luminance, parseThemeSpec,
  installedThemes, installTheme, catalog, art, legacyRootFile, isDir,
};
