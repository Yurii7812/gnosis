// Gnosis 専用 Konsole の新しいウィンドウだけを最大化する KWin 6 script。
// 他の Konsole / Vim ウィンドウは変更しない。ランチャーが 10 秒後にアンロードする。
(function () {
    function maybeMaximize(window) {
        if (!window || !window.normalWindow) return false;
        var cls = String(window.resourceClass || "").toLowerCase();
        if (cls.indexOf("konsole") === -1) return false;
        var title = String(window.caption || "");
        if (title.indexOf("Gnosis") === -1) return false;
        if (window.maximizable) window.setMaximize(true, true);
        return true;
    }

    workspace.windowAdded.connect(function (window) {
        if (!window) return;
        if (maybeMaximize(window)) return;
        // ウィンドウ生成直後はタイトルが未設定の場合がある。
        if (window.captionChanged) {
            window.captionChanged.connect(function () {
                maybeMaximize(window);
            });
        }
    });
})();
