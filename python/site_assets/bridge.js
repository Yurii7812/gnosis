// `\A`（Electron アプリ）の中に iframe として埋め込まれたときだけ働く小さな橋。ふつうのブラウザでは何もしない。
//   iframe の name が "gnosis:open" のとき、ノートのページ（*.html。ビューのページを除く）へのリンクのクリックを、
//   親（アプリ）へ {gnosis:"open", url} で知らせて、そのリンクの通常の移動は止める（親が Vim のタブでそのノートを開く）。
//   それ以外（name が違う・単独で開いている）は何もしない。ビューどうしのリンク・#ハッシュ・外部リンクはそのまま動く。
(function () {
  if (window.parent === window || window.name !== "gnosis:open") return;
  var VIEWS = /(^|\/)(index|cards|table|timeline|graph|fznav|folgezettel|search)\.html$/;
  document.addEventListener("click", function (e) {
    if (e.defaultPrevented || e.button !== 0 || e.ctrlKey || e.metaKey || e.shiftKey) return;
    var a = e.target && e.target.closest ? e.target.closest("a[href]") : null;
    if (!a) return;
    var u;
    try { u = new URL(a.href, location.href); } catch (x) { return; }
    if (u.protocol !== "file:" || !/\.html$/i.test(u.pathname) || VIEWS.test(u.pathname)) return;
    e.preventDefault();
    window.parent.postMessage({ gnosis: "open", url: u.href }, "*");
  }, true);
})();
