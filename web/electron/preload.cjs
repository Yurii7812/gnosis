const { contextBridge, ipcRenderer } = require("electron");

// 画面（renderer）と本体（main）をつなぐ。Vim は main が擬似端末の中で動かす。
contextBridge.exposeInMainWorld("gui", {
  // 端末の大きさが決まったら Vim を起動する
  start: (cols, rows) => ipcRenderer.send("vim:start", cols, rows),
  write: (data) => ipcRenderer.send("pty:write", data),
  resize: (cols, rows) => ipcRenderer.send("pty:resize", cols, rows),
  onData: (cb) => ipcRenderer.on("pty:data", (_e, d) => cb(d)),
  onState: (cb) => ipcRenderer.on("vim:state", (_e, s) => cb(s)),
  onExit: (cb) => ipcRenderer.on("vim:exit", (_e, code) => cb(code)),
  readImage: (file, src) => ipcRenderer.invoke("img:read", file, src),
  quit: () => ipcRenderer.send("app:quit"),
});
