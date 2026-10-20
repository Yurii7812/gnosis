#!/usr/bin/env python3
"""vault のバックアップ・検証・復元（UT04・UT14 の一部）。

- バックアップは tar.gz 1 個 + 同名の `.manifest.json`（全ファイルの相対パス・大きさ・SHA-256・作成日時）。
  対象は vault のノートと添付（ドット始まりのフォルダ・ファイル、`.crypt` などの暗号箱・キャッシュは含めない）。
  暗号化 vault の中身（平文）をバックアップ先に置くときは、出力先の安全は利用者の責任（ここでは暗号化しない）。
- 検証: 書いたアーカイブを読み直して、manifest と全ファイルのハッシュを突き合わせる。検証に失敗したバックアップは
  「成功」と言わない。
- 復元は**新しい空のフォルダ**にだけ行う（既存の vault を上書きしない・消さない）。復元後も manifest で検証する。
- 巨大なバイナリを含むときの目安を出す（`--max-mb` を超えるファイルは一覧に出して、既定ではスキップ。Git LFS・別保管を促す）。
- 元の vault は読むだけで、何も書き換えない。

CLI（JSON）:
  vault_backup.py ROOT backup OUTDIR [--max-mb N]   … OUTDIR/<日時>-<vault名>.tar.gz と .manifest.json を作る
  vault_backup.py verify ARCHIVE                    … アーカイブと manifest を突き合わせる
  vault_backup.py restore ARCHIVE NEWDIR            … 新しい空のフォルダへ復元して検証
  vault_backup.py list OUTDIR                       … 前回までのバックアップの一覧
"""
from __future__ import annotations

import datetime as dt
import hashlib
import io
import json
import os
import sys
import tarfile
from pathlib import Path

MANIFEST_VERSION = 1
DEFAULT_MAX_MB = 200


def _sha256(data: bytes | Path) -> str:
    h = hashlib.sha256()
    if isinstance(data, Path):
        with data.open("rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
    else:
        h.update(data)
    return h.hexdigest()


IGNORE_FILE = ".gnosis/backup-ignore"


def ignore_patterns(root: Path) -> list[str]:
    """バックアップから外すパターン（`<vault>/.gnosis/backup-ignore`。1 行 1 つ・# で始まる行と空行は無視）。
    `大きい動画/`（末尾 / はフォルダ）・`*.mp4`・`下書き/*`・`memo.md` のように、vault からの相対パスに fnmatch で当てる。"""
    try:
        lines = (root / IGNORE_FILE).read_text(encoding="utf-8").split("\n")
    except (OSError, UnicodeDecodeError):
        return []                                    # 読めない除外ファイルでバックアップを止めない（除外なし=多めに含める側に倒す）
    return [ln.strip() for ln in lines if ln.strip() and not ln.strip().startswith("#")]


def _ignored(rel: str, patterns: list[str]) -> bool:
    import fnmatch
    parts = rel.split("/")
    for pat in patterns:
        if pat.endswith("/"):
            d = pat.rstrip("/")
            if any(fnmatch.fnmatchcase("/".join(parts[:i + 1]), d) or fnmatch.fnmatchcase(parts[i], d) for i in range(len(parts) - 1)):
                return True
        elif fnmatch.fnmatchcase(rel, pat) or fnmatch.fnmatchcase(parts[-1], pat):
            return True
    return False


def _files(root: Path):
    """バックアップの対象（相対パス, 絶対パス）。ドット始まりのフォルダ・ファイルとシンボリックリンクは含めない。
    `.gnosis/backup-ignore` のパターンに当たるものも含めない。"""
    patterns = ignore_patterns(root)
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith(".") and not (Path(dirpath) / d).is_symlink())
        for name in sorted(filenames):
            p = Path(dirpath) / name
            if name.startswith(".") or p.is_symlink():
                continue
            rel = p.relative_to(root).as_posix()
            if patterns and _ignored(rel, patterns):
                continue
            yield rel, p


def _manifest_path(archive: Path) -> Path:
    name = archive.name[:-7] if archive.name.endswith(".tar.gz") else archive.name
    return archive.with_name(name + ".manifest.json")


def backup(root: str | Path, outdir: str | Path, max_mb: int = DEFAULT_MAX_MB, now: dt.datetime | None = None) -> dict:
    root = Path(root).resolve()
    out = Path(outdir).resolve()
    if not root.is_dir():
        raise ValueError("vault がありません: " + str(root))
    if out == root or root in out.parents:
        raise ValueError("出力先を vault の中にはできません")
    out.mkdir(parents=True, exist_ok=True)
    now = now or dt.datetime.now()
    stem = f"{now:%Y%m%d%H%M%S}-{root.name}"
    archive = out / (stem + ".tar.gz")
    if archive.exists():
        raise ValueError("すでにあります（上書きしません）: " + str(archive))
    entries, skipped = [], []
    limit = max_mb * 1024 * 1024
    tmp = archive.with_name(archive.name + ".partial")
    try:
        with tarfile.open(tmp, "w:gz") as tar:
            for rel, p in _files(root):
                size = p.stat().st_size
                if size > limit:
                    skipped.append({"path": rel, "size": size})
                    continue
                data = p.read_bytes()      # 読んだ内容そのものを書く（書く前後で変わっても manifest と一致する）
                info = tarfile.TarInfo(rel)
                info.size = len(data)
                info.mtime = int(p.stat().st_mtime)
                info.mode = 0o644
                tar.addfile(info, io.BytesIO(data))
                entries.append({"path": rel, "size": len(data), "sha256": _sha256(data)})
        manifest = {"version": MANIFEST_VERSION, "vault": root.name, "created": now.isoformat(timespec="seconds"),
                    "files": entries, "skipped_large": skipped, "max_mb": max_mb}
        mp = _manifest_path(archive)
        mtmp = mp.with_name(mp.name + ".partial")
        mtmp.write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
        os.replace(tmp, archive)
        os.replace(mtmp, mp)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise
    result = verify(archive)
    if not result["ok"]:
        raise ValueError("バックアップの検証に失敗しました: " + json.dumps(result["problems"][:5], ensure_ascii=False))
    return {"archive": str(archive), "manifest": str(mp), "files": len(entries), "skipped_large": skipped,
            "bytes": archive.stat().st_size, "verified": True}


def verify(archive: str | Path) -> dict:
    """アーカイブを読み直し、manifest と突き合わせる。{ok, files, problems:[{path, problem}]}。"""
    archive = Path(archive)
    mp = _manifest_path(archive)
    problems: list[dict] = []
    if not archive.is_file():
        return {"ok": False, "files": 0, "problems": [{"path": str(archive), "problem": "アーカイブがありません"}]}
    if not mp.is_file():
        return {"ok": False, "files": 0, "problems": [{"path": str(mp), "problem": "manifest がありません"}]}
    try:
        manifest = json.loads(mp.read_text(encoding="utf-8"))
        want = {e["path"]: e for e in manifest["files"]}
    except (ValueError, KeyError):
        return {"ok": False, "files": 0, "problems": [{"path": str(mp), "problem": "manifest が壊れています"}]}
    seen: set[str] = set()
    try:
        with tarfile.open(archive, "r:gz") as tar:
            for m in tar:
                if not m.isfile():
                    problems.append({"path": m.name, "problem": "通常のファイルではありません"})
                    continue
                if m.name.startswith(("/", "..")) or ".." in Path(m.name).parts:
                    problems.append({"path": m.name, "problem": "危険なパスです"})
                    continue
                data = tar.extractfile(m).read()
                e = want.get(m.name)
                if e is None:
                    problems.append({"path": m.name, "problem": "manifest にありません"})
                elif len(data) != e["size"] or _sha256(data) != e["sha256"]:
                    problems.append({"path": m.name, "problem": "内容が manifest と違います（壊れています）"})
                seen.add(m.name)
    except (tarfile.TarError, OSError, EOFError) as ex:
        problems.append({"path": str(archive), "problem": "アーカイブを読めません: " + str(ex)})
    for path in want:
        if path not in seen:
            problems.append({"path": path, "problem": "アーカイブに入っていません"})
    return {"ok": not problems, "files": len(seen), "problems": problems}


def restore(archive: str | Path, newdir: str | Path) -> dict:
    """新しい（無い／空の）フォルダへだけ復元する。既存の中身があれば何もしない。復元後に manifest で検証する。"""
    archive = Path(archive)
    dest = Path(newdir).resolve()
    pre = verify(archive)
    if not pre["ok"]:
        raise ValueError("バックアップが壊れているので復元しません: " + json.dumps(pre["problems"][:3], ensure_ascii=False))
    if dest.exists() and (not dest.is_dir() or any(dest.iterdir())):
        raise ValueError("復元先は無いか空のフォルダにしてください（既存の中身は変えません）: " + str(dest))
    manifest = json.loads(_manifest_path(archive).read_text(encoding="utf-8"))
    want = {e["path"]: e for e in manifest["files"]}
    dest.mkdir(parents=True, exist_ok=True)
    n = 0
    with tarfile.open(archive, "r:gz") as tar:
        for m in tar:
            target = (dest / m.name).resolve()
            target.relative_to(dest)                       # 外へ出るパスは verify で除いてあるが、念のため
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(tar.extractfile(m).read())
            os.utime(target, (m.mtime, m.mtime))
            n += 1
    bad = [p for p, e in want.items() if _sha256(dest / p) != e["sha256"]]
    if bad:
        raise ValueError("復元の検証に失敗しました: " + ", ".join(bad[:5]))
    return {"restored": n, "dest": str(dest), "verified": True, "skipped_large": manifest.get("skipped_large", [])}


def list_backups(outdir: str | Path) -> list[dict]:
    out = []
    for p in sorted(Path(outdir).glob("*.tar.gz")):
        mp = _manifest_path(p)
        info = {"archive": p.name, "bytes": p.stat().st_size, "manifest": mp.is_file()}
        if mp.is_file():
            try:
                m = json.loads(mp.read_text(encoding="utf-8"))
                info.update({"vault": m.get("vault"), "created": m.get("created"), "files": len(m.get("files", []))})
            except ValueError:
                info["manifest"] = False
        out.append(info)
    return out


def main(argv: list[str]) -> int:
    try:
        if len(argv) >= 3 and argv[1] == "backup":
            mb = int(argv[argv.index("--max-mb") + 1]) if "--max-mb" in argv else DEFAULT_MAX_MB
            print(json.dumps(backup(argv[0], argv[2], mb), ensure_ascii=False))
        elif len(argv) == 2 and argv[0] == "verify":
            r = verify(argv[1])
            print(json.dumps(r, ensure_ascii=False))
            return 0 if r["ok"] else 1
        elif len(argv) == 3 and argv[0] == "restore":
            print(json.dumps(restore(argv[1], argv[2]), ensure_ascii=False))
        elif len(argv) == 2 and argv[0] == "list":
            print(json.dumps(list_backups(argv[1]), ensure_ascii=False))
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except (OSError, ValueError) as e:
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
