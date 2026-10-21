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
    private val editFile get() = File(ctx.filesDir, "agenda-edit.tsv")

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

    /**
     * タスクの日時・所要時間・通知・繰り返し・優先度の編集を保存する。PC へ渡す編集の記録(agenda-edit.tsv。PC の agenda_pull.py がノートの行へ書く)に 1 行足し、
     * 手元の予定(agenda.tsv)にも先に反映する(PC が反映して送り直すまでの間も、画面と通知が新しい設定になる)。設定が正しくなければ何もせず false。
     */
    fun saveEdit(key: String, spec: TaskSpec): Boolean {
        val line = Agenda.editLine(key, spec) ?: return false
        val d = load() ?: return false
        if (d.tasks.none { it.key == key }) return false
        return try {
            editFile.appendText(line + "\n")
            val tmp = File(ctx.filesDir, "agenda.tsv.tmp")
            tmp.writeText(Agenda.toTsv(d.copy(tasks = Agenda.applyEdit(d.tasks, key, spec))))
            tmp.renameTo(file)
        } catch (_: Exception) { false }
    }

    /** 完了済みを除いた、いま見せる予定。 */
    fun visible(): AgendaData? = load()?.let { d -> val done = doneKeys(); d.copy(tasks = d.tasks.filter { it.key !in done }) }
}
