package net.gnosis.capture

/**
 * 紙のノートの番号（PC の python/paper_pkm.py と同じ規則）。`PA-1a2` の形: 先頭が印（大文字 1〜4 字。PA・PB…）、あとが番号。
 * 印の無い番号（`1a2`）は、印を付けて使う。画面は、矢印（またはボタン）で「前の番号の子」「次の連番」を付ける。
 */
object PaperId {
    private val BODY = Regex("^[0-9]+([a-z]+[0-9]+)*[a-z]*$")
    private val PREFIXED = Regex("^([A-Z]{1,4})-(.+)$")
    val PREFIX = Regex("^[A-Z]{1,4}$")

    /** `pa-1A2` → `PA-1a2`、`1A2` → `1a2`。 */
    fun normalize(raw: String): String {
        val t = raw.trim()
        val m = Regex("^([A-Za-z]{1,4})-(.+)$").find(t)
        if (m != null && BODY.matches(m.groupValues[2].lowercase())) return m.groupValues[1].uppercase() + "-" + m.groupValues[2].lowercase()
        return t.lowercase()
    }

    /** 番号として正しいか（印つきでも、印なしでも）。 */
    fun isValid(id: String): Boolean {
        val m = PREFIXED.find(id)
        return BODY.matches(if (m != null) m.groupValues[2] else id)
    }

    /** 印の無い番号に印を付ける（もう付いていればそのまま）。 */
    fun withPrefix(prefix: String, id: String): String = if (id.isEmpty() || PREFIXED.matches(id) || prefix.isEmpty()) id else "$prefix-$id"

    /** 前の番号の子（`1a2` → `1a2a`、`1a` → `1a1`）。 */
    fun child(id: String): String = id + (if (id.last().isDigit()) "a" else "1")

    /** 次の連番（`1a2` → `1a3`、`1a` → `1b`、`1z` → `1aa`）。 */
    fun nextSibling(id: String): String {
        val m = Regex("([a-z]+|[0-9]+)$").find(id) ?: return id
        val tail = m.groupValues[1]
        val next = if (tail[0].isDigit()) (tail.toBigInteger() + java.math.BigInteger.ONE).toString() else incrementLetters(tail)
        return id.substring(0, m.range.first) + next
    }

    private fun incrementLetters(letters: String): String {
        val c = letters.toCharArray()
        var i = c.size - 1
        while (i >= 0) {
            if (c[i] != 'z') { c[i] = c[i] + 1; return String(c) }
            c[i] = 'a'
            i--
        }
        return "a" + String(c)
    }
}
