package net.gnosis.capture

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * カレンダー（メモ帳の ⋮ と、予定の画面から開く）。月の表に、その日に書いたメモの数（📔 は日記）と、PC から届いた期限のタスクの数。
 * 日を押すと下にその日の中身: タスク（完了・編集）、メモ（押すとメモ帳のその場所へ）、「この日のタスクを足す」「この日の日記として書く」。
 * ノートは書き換えない（メモとタスクの記録はいつもどおり PC の \M で取り込む）。
 */
class CalendarActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(colorScheme = GnosisColors) {
                Surface(Modifier.fillMaxSize()) { CalendarScreen() }
            }
        }
    }
}

private val WEEK = listOf("月", "火", "水", "木", "金", "土", "日")
private val DAY_TITLE = DateTimeFormatter.ofPattern("M月d日（E）", Locale.JAPAN)

@Composable
private fun CalendarScreen() {
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val store = remember { Store(ctx) }
    val agenda = remember { AgendaStore(ctx) }
    var version by remember { mutableIntStateOf(0) }
    // 戻ってきたとき（メモを書いた・タスクを足した・PC から新しい予定が届いた）に読み直す
    val owner = androidx.compose.ui.platform.LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_RESUME) version++ }
        owner.lifecycle.addObserver(obs)
        onDispose { owner.lifecycle.removeObserver(obs) }
    }
    val today = LocalDate.now()
    var ym by remember { mutableStateOf(YearMonth.from(today)) }
    var sel by remember { mutableStateOf(today) }
    var editing by remember { mutableStateOf<AgendaTask?>(null) }
    val entries = remember(version) { store.load() }
    val tasks = remember(version) { agenda.visible()?.tasks.orEmpty() }
    val stats = remember(ym, entries, tasks) { CalendarModel.month(ym, entries, tasks) }
    val cells = remember(ym) { CalendarModel.cells(ym) }

    LazyColumn(Modifier.fillMaxSize().systemBarsPadding().padding(horizontal = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
                TextButton(onClick = { ym = ym.minusMonths(1) }) { Text("‹", fontSize = 22.sp) }
                Text("${ym.year}年 ${ym.monthValue}月", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                TextButton(onClick = { ym = ym.plusMonths(1) }) { Text("›", fontSize = 22.sp) }
                TextButton(onClick = { ym = YearMonth.from(today); sel = today }) { Text("今日") }
            }
            Row(Modifier.fillMaxWidth()) {
                WEEK.forEachIndexed { i, w ->
                    Text(w, Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center, fontSize = 12.sp,
                        color = when (i) { 5 -> Color(0xFF539BF5); 6 -> Color(0xFFE5534B); else -> MaterialTheme.colorScheme.onSurfaceVariant })
                }
            }
        }
        items(cells.chunked(7)) { week ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                week.forEachIndexed { i, d ->
                    val s = d?.let { stats[it] }
                    val isSel = d == sel
                    val isToday = d == today
                    Column(
                        Modifier.weight(1f).height(58.dp)
                            .background(if (isSel) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerLow, RoundedCornerShape(6.dp))
                            .then(if (isToday) Modifier.border(1.5.dp, MaterialTheme.colorScheme.primary, RoundedCornerShape(6.dp)) else Modifier)
                            .clickable(enabled = d != null) { if (d != null) sel = d }
                            .padding(3.dp),
                    ) {
                        if (d != null) {
                            Text(d.dayOfMonth.toString(), fontSize = 13.sp, fontWeight = if (isToday) FontWeight.Bold else FontWeight.Normal,
                                color = when (i) { 5 -> Color(0xFF539BF5); 6 -> Color(0xFFE5534B); else -> MaterialTheme.colorScheme.onSurface })
                            if (s != null) {
                                if (s.memos > 0) Text((if (s.diary > 0) "📔" else "✎") + s.memos, fontSize = 10.sp, maxLines = 1)
                                if (s.tasks > 0) Text("☐" + s.tasks, fontSize = 10.sp, maxLines = 1, color = if (d.isBefore(today)) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface)
                            }
                        }
                    }
                }
            }
        }
        // 選んだ日
        item {
            HorizontalDivider(Modifier.padding(vertical = 6.dp))
            Text(sel.format(DAY_TITLE), style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 4.dp)) {
                Button(onClick = { ctx.startActivity(Intent(ctx, QuickTaskActivity::class.java).putExtra(QuickTaskActivity.EXTRA_DUE, sel.toString())) }) { Text("＋ この日のタスク") }
                if (!sel.isAfter(today)) OutlinedButton(onClick = {
                    ctx.startActivity(Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        .putExtra(MainActivity.EXTRA_DIARY_DATE, sel.toString()))
                }) { Text(if (sel == today) "日記を書く" else "この日の日記として書く") }
            }
        }
        val dayTasks = CalendarModel.tasksOn(tasks, sel)
        if (dayTasks.isNotEmpty()) item { Text("期限のタスク（${dayTasks.size}）", style = MaterialTheme.typography.labelLarge) }
        items(dayTasks, key = { "t" + it.key }) { t ->
            Card(Modifier.fillMaxWidth().clickable { editing = t }) {
                Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text((if (t.time.isNotEmpty()) t.time + " " else "") + t.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Text(t.note, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    TextButton(onClick = { if (agenda.markDone(t.key)) { version++; AgendaWidget.refresh(ctx) } }) { Text("完了") }
                }
            }
        }
        val dayMemos = CalendarModel.memosOn(entries, sel)
        if (dayMemos.isNotEmpty()) item { Text("この日に書いたメモ（${dayMemos.size}）", style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 6.dp)) }
        items(dayMemos, key = { "m" + it.id }) { e ->
            Card(Modifier.fillMaxWidth().clickable {
                ctx.startActivity(Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra(MainActivity.EXTRA_JUMP, e.id))
            }) {
                Column(Modifier.padding(horizontal = 10.dp, vertical = 6.dp)) {
                    Text(java.text.SimpleDateFormat("HH:mm", Locale.JAPAN).format(java.util.Date(e.created)) + "・" + topicLabel(e.topic),
                        fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(e.text, maxLines = 3, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        if (dayTasks.isEmpty() && dayMemos.isEmpty()) item { Text("この日のメモ・タスクはありません", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        item { Spacer(Modifier.height(24.dp)) }
    }

    editing?.let { t ->
        var spec by remember(t.key) { mutableStateOf(Agenda.specOf(t)) }
        AlertDialog(
            onDismissRequest = { editing = null },
            title = { Text(t.text, maxLines = 2) },
            text = { Column(Modifier.verticalScroll(rememberScrollState())) { TaskEditor(spec) { spec = it } } },
            confirmButton = {
                TextButton(onClick = {
                    if (agenda.saveEdit(t.key, spec)) { AgendaNotifier.scheduleTimed(ctx); AgendaWidget.refresh(ctx); version++ }
                    else android.widget.Toast.makeText(ctx, "保存できませんでした", android.widget.Toast.LENGTH_SHORT).show()
                    editing = null
                }) { Text("保存") }
            },
            dismissButton = { TextButton(onClick = { editing = null }) { Text("やめる") } },
        )
    }
}
