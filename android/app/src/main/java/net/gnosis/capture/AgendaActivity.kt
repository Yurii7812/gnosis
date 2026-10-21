package net.gnosis.capture

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
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
    // 画面に戻ったとき(PC から新しい予定が届いたあと・通知から開いたとき)に、予定を読み直す
    val owner = androidx.compose.ui.platform.LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_RESUME) version++ }
        owner.lifecycle.addObserver(obs)
        onDispose { owner.lifecycle.removeObserver(obs) }
    }
    var prefs by remember { mutableStateOf(AgendaNotifier.load(ctx)) }
    var editing by remember { mutableStateOf<AgendaTask?>(null) }
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
                        Card(Modifier.fillMaxWidth().clickable { editing = t }) {
                            Column(Modifier.padding(12.dp)) {
                                Text(t.text)
                                Text(detail(t), style = MaterialTheme.typography.bodySmall)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    TextButton(onClick = { if (store.markDone(t.key)) { version++; AgendaWidget.refresh(ctx) } }) { Text("完了") }
                                    var menu by remember { mutableStateOf(false) }
                                    Box {
                                        TextButton(onClick = { menu = true }) { Text("スヌーズ") }
                                        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                            for (m in Agenda.SNOOZE_CHOICES) DropdownMenuItem(text = { Text("$m 分後にもう一度") }, onClick = { menu = false; AgendaNotifier.snooze(ctx, t, m) })
                                        }
                                    }
                                    TextButton(onClick = { editing = t }) { Text("編集") }
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
            // 「アラームとリマインダー」が許可されていないと、通知が数分〜十数分ずれることがある(Android の仕様)。許可は利用者が設定画面で行う
            if (!Alarm.canScheduleExact(ctx)) {
                Text("今は通知が数分〜十数分ずれることがあります。時刻どおりに知らせるには、設定の「アラームとリマインダー」を許可してください。", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                TextButton(onClick = {
                    try { ctx.startActivity(Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, android.net.Uri.parse("package:" + ctx.packageName))) }
                    catch (_: Exception) { ctx.startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:" + ctx.packageName))) }
                }) { Text("許可の設定を開く") }
            }
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
                Text("  タスクごとに設定した通知（時刻ちょうど・10 分前など）を出す")
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

    // タスクの編集（日付・時刻・所要時間・通知・繰り返し・優先度）。保存すると、手元の画面と通知にすぐ反映し、PC へは次の :GnosisPullDone でノートの行に書かれる
    editing?.let { t ->
        var spec by remember(t.key) { mutableStateOf(Agenda.specOf(t)) }
        AlertDialog(
            onDismissRequest = { editing = null },
            title = { Text(t.text, maxLines = 2) },
            text = { Column(Modifier.verticalScroll(rememberScrollState())) { TaskEditor(spec) { spec = it } } },
            confirmButton = {
                TextButton(onClick = {
                    if (store.saveEdit(t.key, spec)) { AgendaNotifier.scheduleTimed(ctx); AgendaWidget.refresh(ctx); version++ }
                    else android.widget.Toast.makeText(ctx, "保存できませんでした", android.widget.Toast.LENGTH_SHORT).show()
                    editing = null
                }) { Text("保存") }
            },
            dismissButton = { TextButton(onClick = { editing = null }) { Text("やめる") } },
        )
    }
}

/** カードの 2 行目: 日付・時刻・所要時間・繰り返し・通知・ノートの題。 */
private fun detail(t: AgendaTask): String {
    val parts = ArrayList<String>()
    if (t.due.isNotEmpty()) parts.add(t.due + (if (t.time.isNotEmpty()) " " + t.time + (if (t.duration > 0) "〜" + endTime(t) else "") else ""))
    if (t.duration > 0 && t.time.isEmpty()) parts.add(Agenda.fmtDuration(t.duration))
    if (t.repeat.isNotEmpty()) parts.add("🔁 " + repeatLabel(t.repeat))
    if (t.reminds == "none") parts.add("通知なし") else if (t.reminds.isNotEmpty()) parts.add("🔔 " + (Agenda.parseReminds(t.reminds) ?: emptyList()).joinToString("・") { Agenda.offsetLabel(it) })
    parts.add(t.note)
    return parts.joinToString("・")
}

private fun endTime(t: AgendaTask): String = runCatching { java.time.LocalTime.parse(t.time).plusMinutes(t.duration.toLong()).toString() }.getOrDefault("")

private fun repeatLabel(r: String) = when (r) { "daily" -> "毎日"; "weekly" -> "毎週"; "monthly" -> "毎月"; "yearly" -> "毎年"; "weekday" -> "平日"; else -> r }
