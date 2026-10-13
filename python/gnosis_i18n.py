"""Gnosis の補助スクリプトの文言（日本語 / 英語）。

Vim（gnosis#i18n#set_lang）が環境変数 GNOSIS_LANG に vault の言語を入れる。
    from gnosis_i18n import tr
    print(tr("日本語", "English"))
"""
import os


def lang() -> str:
    return "en" if os.environ.get("GNOSIS_LANG") == "en" else "ja"


def tr(ja: str, en: str) -> str:
    return en if lang() == "en" else ja
