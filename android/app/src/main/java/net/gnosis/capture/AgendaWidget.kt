package net.gnosis.capture

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.time.LocalDate
import java.time.LocalDateTime

/** ホーム画面のウィジェット: 今日の予定の件数と上位 4 件。押すと予定の画面、「＋」でクイックタスク追加。PC の予定がまだ届いていなければ、そう表示する。 */
class AgendaWidget : AppWidgetProvider() {
    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) { ids.forEach { mgr.updateAppWidget(it, views(ctx)) } }

    companion object {
        private val LINES = intArrayOf(R.id.w_t1, R.id.w_t2, R.id.w_t3, R.id.w_t4)

        fun lines(data: AgendaData?, today: LocalDate, now: LocalDateTime): Pair<String, List<String>> {
            if (data == null) return "PC の予定がまだ届いていません" to emptyList()
            val b = Agenda.bucket(data.tasks, today)
            val stale = Agenda.staleDays(data, now)
            val head = Agenda.summary(b) + if (stale != null && stale >= 3) "（${stale} 日前の予定）" else ""
            return head to (b.overdue + b.today + b.soon).take(4).map { (if (it.due.isNotEmpty() && it.due < today.toString()) "⚠ " else "・") + it.text }
        }

        private fun views(ctx: Context): RemoteViews {
            val rv = RemoteViews(ctx.packageName, R.layout.agenda_widget)
            val (head, tasks) = lines(AgendaStore(ctx).visible(), LocalDate.now(), LocalDateTime.now())
            rv.setTextViewText(R.id.w_head, head)
            LINES.forEachIndexed { i, id -> rv.setTextViewText(id, tasks.getOrNull(i) ?: "") }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            rv.setOnClickPendingIntent(R.id.w_root, PendingIntent.getActivity(ctx, 5201, Intent(ctx, AgendaActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), flags))
            rv.setOnClickPendingIntent(R.id.w_add, PendingIntent.getActivity(ctx, 5202, Intent(ctx, QuickTaskActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), flags))
            return rv
        }

        fun refresh(ctx: Context) {
            val mgr = AppWidgetManager.getInstance(ctx)
            mgr.getAppWidgetIds(ComponentName(ctx, AgendaWidget::class.java)).forEach { mgr.updateAppWidget(it, views(ctx)) }
        }
    }
}
