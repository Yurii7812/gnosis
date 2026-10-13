#!/usr/bin/env python3
"""folgezettel_scan.py の「日記として登録」の GUI テスト（tkinter・Pillow が要る。表示が無い環境では xvfb で）。

    xvfb-run -a python3 test_folgezettel_scan_diary.py

一時フォルダだけを使う（本物の vault には触らない）。ダイアログ（messagebox）は差し替えて自動で閉じる。
"""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

_FAILED: list[str] = []


def check(cond: bool, msg: str) -> None:
    if cond:
        print(f"  ok   {msg}")
    else:
        print(f"  FAIL {msg}")
        _FAILED.append(msg)


def main() -> int:
    try:
        import tkinter as tk
        from PIL import Image
    except Exception as exc:  # noqa: BLE001
        print(f"skip: tkinter / Pillow が使えない ({exc})")
        return 0
    import folgezettel_scan as fs
    import paper_pkm as pp

    try:
        root_tk = tk.Tk()
    except tk.TclError as exc:
        print(f"skip: 表示が無い ({exc})。xvfb-run -a で実行すると動く")
        return 0
    root_tk.withdraw()
    # ダイアログは出さず、すべて OK / はい として扱う
    for name in ("showinfo", "showwarning", "showerror"):
        setattr(fs.messagebox, name, lambda *a, **k: None)
    fs.messagebox.askyesno = lambda *a, **k: True

    print("gui: 日記として登録（複数ページ）＋ 通常の ID 登録 → 移動して同期")
    with tempfile.TemporaryDirectory() as d:
        vault = Path(d) / "vault"
        scans = Path(d) / "scans"
        vault.mkdir()
        scans.mkdir()
        (vault / "index.md").write_text("---\ntitle: Index\nattribute: group\n---\n\n# Index\n", encoding="utf-8")
        idx = pp.create_paper_index(vault)
        for i in range(1, 5):
            Image.new("RGB", (40, 30), (i * 40, 0, 0)).save(scans / f"s{i}.jpg")
        app = fs.ScanApp(root_tk, vault, vault)
        app.load_folder(scans, ask_resume=False)
        check(len(app.items) == 4, "4 枚読み込まれる")
        app.start_naming()
        # 1 枚目: 通常の ID
        app.commit_id("1")
        # 2・3 枚目: 同じ日の日記の 2 ページ。d の入力欄は、直前の日記の日付を既定にする
        app.show_diary_input()
        check(app.diary_date_var.get() == __import__("datetime").datetime.now().strftime("%Y-%m-%d"), "最初の既定は今日")
        app.diary_date_var.set("2026/10/07")
        app.confirm_diary()
        app.show_diary_input()
        check(app.diary_date_var.get() == "2026-10-07", "続きのページの既定は直前の日記の日付")
        app.confirm_diary()
        check(app.items[1].diary_date == "2026-10-07" and app.items[2].diary_date == "2026-10-07"
              and app.items[1].current_name == "paper-diary-20261007-1.jpg"
              and app.items[2].current_name == "paper-diary-20261007-2.jpg", "ページ番号が続く")
        # 不正な日付は受け付けない
        app.show_diary_input()
        app.diary_date_var.set("2026-13-99")
        app.confirm_diary()
        check(app.current_index == 3 and app.input_active, "不正な日付は確定されず入力欄のまま")
        # 取り消し: 日記の登録を戻せる
        app.hide_input()
        app.undo_last()
        check(app.items[2].diary_date is None and not app.items[2].processed and (scans / "s3.jpg").exists(),
              "← で日記の登録を取り消すと元の名前・未処理に戻る")
        app.show_diary_input()
        app.diary_date_var.set("2026-10-07")
        app.confirm_diary()
        # 4 枚目: 別の日の日記
        app.show_diary_input()
        app.diary_date_var.set("2026-09-30")
        app.confirm_diary()
        app.move_processed(auto=True)

        notes = pp.scan_diary_notes(vault)
        check(set(notes) == {"2026-10-07", "2026-09-30"}, f"日記ノートができる: {sorted(notes)}")
        n = notes["2026-10-07"].read_text(encoding="utf-8")
        check("paper-diary-20261007-1.jpg" in n and "paper-diary-20261007-2.jpg" in n, "複数ページが 1 ノートに入る")
        check((vault / "paper-diary-20261007-1.jpg").is_file() and (vault / "1.jpg").is_file(), "日記の画像と通常の ID 画像が vault へ移る")
        check(pp.scan_folgezettel_notes(vault).keys() == {"1"}, "通常の ID 登録は今までどおり")
        itext = idx.read_text(encoding="utf-8")
        check(idx.name == "Paper-Zettelkasten-Index.md" and itext.count("[日記](") == 1, "Index にキーワード「日記」が 1 つ")
        check(not any(it.processed for it in app.items), "移動した分は作業一覧から消える")
    root_tk.destroy()
    print()
    if _FAILED:
        print(f"{len(_FAILED)} FAILED")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
