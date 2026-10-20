package net.gnosis.capture

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import java.time.LocalDateTime
import java.time.ZoneId

/** 予定の通知の設定（朝の通知・静かな時間）。 */
data class AgendaPrefs(val morningOn: Boolean = false, val hour: Int = 7, val minute: Int = 30, val timedOn: Boolean = true, val quietFrom: Int = 22, val quietTo: Int = 7)

/**
 * 予定の通知。朝のまとめ（期限切れ・今日）、時刻つきのタスクの直前の通知（「完了」「10 分後に」を押せる）。
 * 既定はどれもオフ（朝）／静かな時間は夜 22 時〜朝 7 時は時刻つきの通知を出さない（通知の集中設定）。
 * 通知を押すと予定の画面（AgendaActivity）が開く。
 */
object AgendaNotifier {
    const val CHANNEL = "gnosis_agenda_v1"
    private const val REQ_MORNING = 5101
    private const val NOTIF_MORNING = 5102
    private const val ACTION_DONE = "net.gnosis.capture.AGENDA_DONE"
    private const val ACTION_SNOOZE = "net.gnosis.capture.AGENDA_SNOOZE"
    const val EXTRA_KEY = "key"
    const val EXTRA_TEXT = "text"
    const val EXTRA_NOTE = "note"
    private fun prefs(ctx: Context) = ctx.getSharedPreferences("agenda", Context.MODE_PRIVATE)

    fun load(ctx: Context): AgendaPrefs {
        val p = prefs(ctx)
        return AgendaPrefs(p.getBoolean("morningOn", false), p.getInt("hour", 7), p.getInt("minute", 30), p.getBoolean("timedOn", true), p.getInt("quietFrom", 22), p.getInt("quietTo", 7))
    }

    fun save(ctx: Context, s: AgendaPrefs) {
        prefs(ctx).edit().putBoolean("morningOn", s.morningOn).putInt("hour", s.hour.coerceIn(0, 23)).putInt("minute", s.minute.coerceIn(0, 59))
            .putBoolean("timedOn", s.timedOn).putInt("quietFrom", s.quietFrom.coerceIn(0, 24)).putInt("quietTo", s.quietTo.coerceIn(0, 24)).apply()
        scheduleMorning(ctx)
        scheduleTimed(ctx)
    }

    private fun ensureChannel(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL) == null) {
            val ch = NotificationChannel(CHANNEL, "予定", NotificationManager.IMPORTANCE_DEFAULT)
            ch.description = "朝のまとめと、時刻つきのタスクの知らせ"
            nm.createNotificationChannel(ch)
        }
    }

    private fun openAgenda(ctx: Context, req: Int): PendingIntent =
        PendingIntent.getActivity(ctx, req, Intent(ctx, AgendaActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun alarm(ctx: Context, atMillis: Long, pi: PendingIntent) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        try {
            if (Alarm.canScheduleExact(ctx)) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pi)
            else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pi)
        } catch (_: SecurityException) { am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pi) }
    }

    private fun millis(t: LocalDateTime) = t.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()

    // ---- 朝のまとめ ----
    private fun morningPending(ctx: Context) = PendingIntent.getBroadcast(ctx, REQ_MORNING, Intent(ctx, AgendaMorningReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun scheduleMorning(ctx: Context) {
        val s = load(ctx)
        ctx.getSystemService(AlarmManager::class.java).cancel(morningPending(ctx))
        if (!s.morningOn) return
        alarm(ctx, millis(Agenda.nextMorning(s.hour, s.minute, LocalDateTime.now())), morningPending(ctx))
    }

    fun notifyMorning(ctx: Context) {
        val data = AgendaStore(ctx).visible() ?: return
        val msg = Agenda.morningMessage(data, LocalDateTime.now().toLocalDate()) ?: return          // 今日・期限切れが無ければ出さない
        ensureChannel(ctx)
        val n = NotificationCompat.Builder(ctx, CHANNEL).setSmallIcon(R.drawable.ic_note).setContentTitle(msg.first).setContentText(msg.second.lineSequence().first())
            .setStyle(NotificationCompat.BigTextStyle().bigText(msg.second)).setContentIntent(openAgenda(ctx, REQ_MORNING + 1)).setAutoCancel(true).build()
        try { ctx.getSystemService(NotificationManager::class.java).notify(NOTIF_MORNING, n) } catch (_: SecurityException) { }
    }

    // ---- 時刻つきのタスク ----
    private fun timedPending(ctx: Context, key: String, text: String, note: String) =
        PendingIntent.getBroadcast(ctx, 6000 + (key.hashCode() and 0xfff), Intent(ctx, AgendaTimedReceiver::class.java).putExtra(EXTRA_KEY, key).putExtra(EXTRA_TEXT, text).putExtra(EXTRA_NOTE, note),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    /** 今日のこれから先の、時刻つきのタスクの知らせを予約し直す（前の予約は消す）。 */
    fun scheduleTimed(ctx: Context) {
        val p = prefs(ctx)
        val am = ctx.getSystemService(AlarmManager::class.java)
        p.getStringSet("timed", emptySet())!!.forEach { k -> am.cancel(timedPending(ctx, k, "", "")) }
        if (!load(ctx).timedOn) { p.edit().remove("timed").apply(); return }
        val data = AgendaStore(ctx).visible() ?: return
        val now = LocalDateTime.now()
        val plan = Agenda.timedToday(data.tasks, now.toLocalDate(), now, 10)
        plan.forEach { (at, t) -> alarm(ctx, millis(at), timedPending(ctx, t.key, t.text, t.note)) }
        p.edit().putStringSet("timed", plan.map { it.second.key }.toSet()).apply()
    }

    fun notifyTask(ctx: Context, key: String, text: String, note: String) {
        val s = load(ctx)
        if (AlarmTiming.inside(s.quietFrom, s.quietTo, LocalDateTime.now().hour) && s.quietFrom != s.quietTo) return    // 静かな時間は出さない
        if (key in AgendaStore(ctx).doneKeys()) return                                                                     // もう完了を押したものは出さない
        ensureChannel(ctx)
        fun act(action: String, label: String, req: Int) = NotificationCompat.Action.Builder(0, label,
            PendingIntent.getBroadcast(ctx, req + (key.hashCode() and 0xfff), Intent(ctx, AgendaActionReceiver::class.java).setAction(action).putExtra(EXTRA_KEY, key).putExtra(EXTRA_TEXT, text).putExtra(EXTRA_NOTE, note),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)).build()
        val n = NotificationCompat.Builder(ctx, CHANNEL).setSmallIcon(R.drawable.ic_note).setContentTitle(text).setContentText(note)
            .setContentIntent(openAgenda(ctx, REQ_MORNING + 2)).setAutoCancel(true).addAction(act(ACTION_DONE, "完了", 7000)).addAction(act(ACTION_SNOOZE, "10 分後に", 8000)).build()
        try { ctx.getSystemService(NotificationManager::class.java).notify(9000 + (key.hashCode() and 0xfff), n) } catch (_: SecurityException) { }
    }

    fun onAction(ctx: Context, action: String?, key: String, text: String, note: String) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.cancel(9000 + (key.hashCode() and 0xfff))
        when (action) {
            ACTION_DONE -> { AgendaStore(ctx).markDone(key); AgendaWidget.refresh(ctx) }
            ACTION_SNOOZE -> alarm(ctx, millis(Agenda.snoozeAt(LocalDateTime.now(), 10)), timedPending(ctx, key, text, note))
        }
    }

    /** 画面からの「10 分後に」。 */
    fun snooze(ctx: Context, t: AgendaTask, minutes: Int = 10) = alarm(ctx, millis(Agenda.snoozeAt(LocalDateTime.now(), minutes)), timedPending(ctx, t.key, t.text, t.note))
}

class AgendaMorningReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        try { AgendaNotifier.notifyMorning(ctx); AgendaNotifier.scheduleTimed(ctx); AgendaWidget.refresh(ctx) } finally { AgendaNotifier.scheduleMorning(ctx) }
    }
}

class AgendaTimedReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        AgendaNotifier.notifyTask(ctx, intent.getStringExtra(AgendaNotifier.EXTRA_KEY) ?: return, intent.getStringExtra(AgendaNotifier.EXTRA_TEXT) ?: "", intent.getStringExtra(AgendaNotifier.EXTRA_NOTE) ?: "")
    }
}

class AgendaActionReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        AgendaNotifier.onAction(ctx, intent.action, intent.getStringExtra(AgendaNotifier.EXTRA_KEY) ?: return, intent.getStringExtra(AgendaNotifier.EXTRA_TEXT) ?: "", intent.getStringExtra(AgendaNotifier.EXTRA_NOTE) ?: "")
    }
}
