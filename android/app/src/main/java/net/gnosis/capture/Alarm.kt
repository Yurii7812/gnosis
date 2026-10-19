package net.gnosis.capture

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import java.util.Calendar

/**
 * 定期の通知（初期は鳴らさない）。設定の間隔（分）ごとに、起きている時間帯（fromHour〜toHour）だけ鳴らす。
 * 通知を押すと「今まで何してた？」の書く画面が日記トピックで開く。
 */
object Alarm {
    const val CHANNEL = "gnosis_capture_alarm"
    const val EXTRA_PROMPT = "prompt"
    private const val REQ = 4201

    fun ensureChannel(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL) == null) {
            val ch = NotificationChannel(CHANNEL, "定期のメモ", NotificationManager.IMPORTANCE_HIGH)
            ch.description = "今まで何をしていたかを書くための通知"
            nm.createNotificationChannel(ch)
        }
    }

    private fun pending(ctx: Context): PendingIntent =
        PendingIntent.getBroadcast(ctx, REQ, Intent(ctx, AlarmReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    /** 次に鳴らす時刻（今から間隔ぶん後。時間帯の外なら、次の開始時刻）。 */
    fun nextTime(s: Settings, now: Long = System.currentTimeMillis()): Long {
        val c = Calendar.getInstance().apply { timeInMillis = now + s.alarmMinutes * 60_000L }
        val h = c.get(Calendar.HOUR_OF_DAY)
        val inside = if (s.fromHour <= s.toHour) h in s.fromHour until s.toHour else (h >= s.fromHour || h < s.toHour)
        if (!inside) {
            if (h >= s.fromHour && s.fromHour <= s.toHour) c.add(Calendar.DAY_OF_YEAR, 1)
            c.set(Calendar.HOUR_OF_DAY, s.fromHour); c.set(Calendar.MINUTE, 0); c.set(Calendar.SECOND, 0)
        }
        return c.timeInMillis
    }

    fun schedule(ctx: Context, s: Settings) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        am.cancel(pending(ctx))
        if (!s.alarmOn) return
        // 厳密な時刻の許可は要らない（数分のずれは問題にならない）
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextTime(s), pending(ctx))
    }

    fun notify(ctx: Context) {
        ensureChannel(ctx)
        val open = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_PROMPT, true)
        }
        val pi = PendingIntent.getActivity(ctx, REQ + 1, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(ctx, CHANNEL)
            .setSmallIcon(R.drawable.ic_note)
            .setContentTitle("今まで何してた？")
            .setContentText("押すと日記に書けます")
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        try {
            ctx.getSystemService(NotificationManager::class.java).notify(REQ, n)
        } catch (_: SecurityException) {
        }
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val s = Store(ctx).loadSettings()
        if (!s.alarmOn) return
        Alarm.notify(ctx)
        Alarm.schedule(ctx, s)
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        Alarm.schedule(ctx, Store(ctx).loadSettings())
    }
}
