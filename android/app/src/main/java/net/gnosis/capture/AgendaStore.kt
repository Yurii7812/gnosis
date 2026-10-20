package net.gnosis.capture

import android.content.Context
import java.io.File
import java.time.LocalDateTime

/**
 * PC から届いた予定（files/agenda.tsv）と、スマホで押した「完了」の記録（files/agenda-done.tsv）。
 * 完了の記録は PC の python/agenda_pull.py が読んで、ノートのタスクを完了にする（このアプリはノートを持っていないので書き換えない）。
 * 次に PC から予定が届くまでは、完了を押したものを画面・通知・ウィジェットから隠す。
 */
class AgendaStore(private val ctx: Context) {
    private val file get() = File(ctx.filesDir, "agenda.tsv")
    private val doneFile get() = File(ctx.filesDir, "agenda-done.tsv")

    fun load(): AgendaData? = try { if (file.exists()) Agenda.parse(file.readText()) else null } catch (_: Exception) { null }

    /** 完了を押したキー（PC がまだ取り込んでいないもの）。 */
    fun doneKeys(): Set<String> = try {
        if (!doneFile.exists()) emptySet()
        else doneFile.readLines().mapNotNull { ln -> ln.split("\t").takeIf { it.size >= 2 && it[0] == "done" }?.get(1) }.toSet()
    } catch (_: Exception) { emptySet() }

    /** 完了の記録を 1 行足す。追記（O_APPEND）なので、PC が読むために名前を変えた直後でも、新しいファイルに入る。 */
    fun markDone(key: String, now: LocalDateTime = LocalDateTime.now()): Boolean {
        val line = Agenda.doneLine(key, now) ?: return false
        return try { doneFile.appendText(line + "\n"); true } catch (_: Exception) { false }
    }

    /** 完了済みを除いた、いま見せる予定。 */
    fun visible(): AgendaData? = load()?.let { d -> val done = doneKeys(); d.copy(tasks = d.tasks.filter { it.key !in done }) }
}
