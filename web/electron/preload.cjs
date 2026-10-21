const { contextBridge, ipcRenderer } = require("electron");

// 画面（renderer）と本体（main）をつなぐ。Vim は main が擬似端末の中で動かす。
contextBridge.exposeInMainWorld("gui", {
  // 端末の大きさが決まったら Vim を起動する（vault … 起動画面で選んだ vault のパス）
  start: (cols, rows, vault) => ipcRenderer.send("vim:start", cols, rows, vault || ""),
  write: (data) => ipcRenderer.send("pty:write", data),
  resize: (cols, rows) => ipcRenderer.send("pty:resize", cols, rows),
  onData: (cb) => ipcRenderer.on("pty:data", (_e, d) => cb(d)),
  onState: (cb) => ipcRenderer.on("vim:state", (_e, s) => cb(s)),
  onExit: (cb) => ipcRenderer.on("vim:exit", (_e, code) => cb(code)),
  readImage: (file, src) => ipcRenderer.invoke("img:read", file, src),
  quit: () => ipcRenderer.send("app:quit"),
  // GUI 編集モード
  enterEdit: () => ipcRenderer.invoke("gui:enter"),
  leaveEdit: () => ipcRenderer.invoke("gui:leave"),
  readNote: (file) => ipcRenderer.invoke("note:read", file),
  commitNote: (file, text, hash, force) => ipcRenderer.invoke("note:commit", file, text, hash, !!force),
  resolveLink: (file, href) => ipcRenderer.invoke("note:resolve", file, href),
  asideNote: (file, text) => ipcRenderer.invoke("note:aside", file, text),
  openNote: (file) => ipcRenderer.invoke("note:open", file),
  // ワークスペース（タブ・分割）・表示専用ビューの元サイト・コマンドパレット
  loadWorkspace: () => ipcRenderer.invoke("workspace:load"),
  saveWorkspace: (text) => ipcRenderer.invoke("workspace:save", text),
  viewSite: (force) => ipcRenderer.invoke("view:site", !!force),
  vimCommands: () => ipcRenderer.invoke("cmds:vim"),
  // 索引ナビ・索引ブラウザ・カレンダー・曼荼羅・キャンバス（読むのは app_model.py、書くのは Vim の gnosis#app_op）
  query: (method, params) => ipcRenderer.invoke("app:query", method, params || {}),
  op: (op, params) => ipcRenderer.invoke("app:op", op, params || {}),
  noteRoot: () => ipcRenderer.invoke("app:root"),
  // 試験だけ（GNOSIS_TEST_SHOTS のとき main が受け付ける）: 今の画面を撮る
  testShot: (name) => ipcRenderer.invoke("test:shot", String(name)),
});

// 起動画面・vault の選択と管理・設定
contextBridge.exposeInMainWorld("gnosis", {
  state: (selected) => ipcRenderer.invoke("launcher:state", selected || ""),
  pickFolder: (title) => ipcRenderer.invoke("vault:pick", title || ""),
  addVault: (p) => ipcRenderer.invoke("vault:add", p),
  createVault: (p, lang) => ipcRenderer.invoke("vault:create", p, lang || ""),
  removeVault: (p) => ipcRenderer.invoke("vault:remove", p),
  selectVault: (p) => ipcRenderer.invoke("vault:select", p),
  saveSettings: (vault, s) => ipcRenderer.invoke("settings:save", vault, s),
  installTheme: (spec) => ipcRenderer.invoke("theme:install", spec),
  palette: (s) => ipcRenderer.invoke("theme:palette", s),
  appPalette: (s) => ipcRenderer.invoke("theme:appPalette", s),
});
