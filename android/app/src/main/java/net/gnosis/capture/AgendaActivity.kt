package net.gnosis.capture

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import java.time.LocalDateTime

/**
 * 予定の画面（通知・ウィジェットから開く）。PC の Gnosis から届いた未完了のタスクを、期限切れ・今日・7 日以内・それ以降・期限なしで見せる。
 * 「完了」はこのアプリのメモ帳に記録するだけで、ノートは書き換えない（PC の `agenda_pull.py` がノートへ反映する）。
 * 朝の通知と静かな時間の設定、クイックタスク追加（メモとして保存。PC の \M で取り込むとタスクになる）もここから。
 */
class AgendaActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val dark = isSystemInDarkTheme()
            MaterialTheme(colorScheme = if (dark) darkColorScheme() else lightColorScheme()) {
                Surface(Modifier.fillMaxSize()) { AgendaScreen() }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        AgendaNotifier.scheduleMorning(this)
        AgendaNotifier.scheduleTimed(this)
        AgendaWidget.refresh(this)
    }
}

@Composable
private fun AgendaScreen() {
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val store = remember { AgendaStore(ctx) }
    var version by remember { mutableIntStateOf(0) }
    var prefs by remember { mutableStateOf(AgendaNotifier.load(ctx)) }
    val data = remember(version) { store.visible() }
    val today = LocalDate.now()
    val b = remember(data, version) { data?.let { Agenda.bucket(it.tasks, today) } }
    LazyColumn(Modifier.fillMaxSize().systemBarsPadding().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            Text("予定", style = MaterialTheme.typography.headlineSmall)
            if (data == null) Text("PC の予定がまだ届いていません。PC で :GnosisPushAgenda を実行してください。", color = MaterialTheme.colorScheme.error)
            else {
                Text(Agenda.summary(b!!))
                val stale = Agenda.staleDays(data, LocalDateTime.now())
                if (stale != null && stale >= 3) Text("PC の予定は $stale 日前のものです。", color = MaterialTheme.colorScheme.error)
            }
            Spacer(Modifier.height(4.dp))
            Button(onClick = { ctx.startActivity(Intent(ctx, QuickTaskActivity::class.java)) }) { Text("＋ タスクを足す") }
        }
        if (b != null) {
            listOf("期限切れ" to b.overdue, "今日" to b.today, "7 日以内" to b.soon, "それ以降" to b.later, "期限なし" to b.undated).forEach { (label, tasks) ->
                if (tasks.isNotEmpty()) {
                    item { Text("$label（${tasks.size}）", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp)) }
                    items(tasks, key = { it.key }) { t ->
                        Card(Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(12.dp)) {
                                Text(t.text)
                                Text((if (t.due.isNotEmpty()) t.due + (if (t.time.isNotEmpty()) " " + t.time else "") + "・" else "") + t.note, style = MaterialTheme.typography.bodySmall)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    TextButton(onClick = { if (store.markDone(t.key)) { version++; AgendaWidget.refresh(ctx) } }) { Text("完了") }
                                    TextButton(onClick = { AgendaNotifier.snooze(ctx, t) }) { Text("10 分後に知らせる") }
                                }
                            }
                        }
                    }
                }
            }
        }
        item {
            HorizontalDivider(Modifier.padding(vertical = 8.dp))
            Text("通知", style = MaterialTheme.typography.titleMedium)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = prefs.morningOn, onCheckedChange = { prefs = prefs.copy(morningOn = it); AgendaNotifier.save(ctx, prefs) })
                Text("  朝のまとめ（今日・期限切れ）")
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("時刻 %02d:%02d".format(prefs.hour, prefs.minute))
                TextButton(onClick = { prefs = prefs.copy(hour = (prefs.hour + 23) % 24); AgendaNotifier.save(ctx, prefs) }) { Text("時 −") }
                TextButton(onClick = { prefs = prefs.copy(hour = (prefs.hour + 1) % 24); AgendaNotifier.save(ctx, prefs) }) { Text("時 ＋") }
                TextButton(onClick = { prefs = prefs.copy(minute = (prefs.minute + 55) % 60); AgendaNotifier.save(ctx, prefs) }) { Text("分 −") }
                TextButton(onClick = { prefs = prefs.copy(minute = (prefs.minute + 5) % 60); AgendaNotifier.save(ctx, prefs) }) { Text("分 ＋") }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = prefs.timedOn, onCheckedChange = { prefs = prefs.copy(timedOn = it); AgendaNotifier.save(ctx, prefs) })
                Text("  時刻つきのタスクの直前に知らせる")
            }
            Text("静かな時間（時刻つきの通知を出さない）: ${prefs.quietFrom} 時〜${prefs.quietTo} 時", style = MaterialTheme.typography.bodySmall)
            Row {
                TextButton(onClick = { prefs = prefs.copy(quietFrom = (prefs.quietFrom + 23) % 24); AgendaNotifier.save(ctx, prefs) }) { Text("開始 −") }
                TextButton(onClick = { prefs = prefs.copy(quietFrom = (prefs.quietFrom + 1) % 24); AgendaNotifier.save(ctx, prefs) }) { Text("開始 ＋") }
                TextButton(onClick = { prefs = prefs.copy(quietTo = (prefs.quietTo + 23) % 24); AgendaNotifier.save(ctx, prefs) }) { Text("終了 −") }
                TextButton(onClick = { prefs = prefs.copy(quietTo = (prefs.quietTo + 1) % 24); AgendaNotifier.save(ctx, prefs) }) { Text("終了 ＋") }
            }
        }
    }
}
