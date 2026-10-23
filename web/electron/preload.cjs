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
  scan: (cmd, args) => ipcRenderer.invoke("scan:run", cmd, args || []),
  scanImage: (name) => ipcRenderer.invoke("scan:image", name),
  quit: () => ipcRenderer.send("app:quit"),
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
