package net.gnosis.capture

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import java.time.LocalDate

/**
 * タスクの日時・所要時間・通知・繰り返し・優先度を選ぶ部品（Google カレンダーの予定の設定のように）。予定の画面の「編集」とクイック追加で共通。
 * 値の意味と検証は Agenda.kt（純粋なロジック）。ここは見せて選ばせるだけ。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TaskEditor(spec: TaskSpec, onChange: (TaskSpec) -> Unit) {
    val ctx = LocalContext.current
    val today = LocalDate.now()
    fun setDue(d: String) = onChange(spec.copy(due = d, time = if (d.isEmpty()) "" else spec.time))

    @Composable fun Heading(t: String) = Text(t, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 6.dp))
    @Composable fun Chip(label: String, on: Boolean, click: () -> Unit) = FilterChip(selected = on, onClick = click, label = { Text(label) })

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Heading("日付")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Chip("なし", spec.due.isEmpty()) { setDue("") }
            Chip("今日", spec.due == today.toString()) { setDue(today.toString()) }
            Chip("明日", spec.due == today.plusDays(1).toString()) { setDue(today.plusDays(1).toString()) }
            Chip("来週", spec.due == today.plusDays(7).toString()) { setDue(today.plusDays(7).toString()) }
            val custom = spec.due.isNotEmpty() && spec.due !in listOf(today, today.plusDays(1), today.plusDays(7)).map { it.toString() }
            Chip(if (custom) spec.due else "日付を選ぶ…", custom) {
                val base = runCatching { LocalDate.parse(spec.due) }.getOrDefault(today)
                DatePickerDialog(ctx, { _, y, m, d -> setDue(LocalDate.of(y, m + 1, d).toString()) }, base.year, base.monthValue - 1, base.dayOfMonth).show()
            }
        }
        Heading("時刻")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(enabled = spec.due.isNotEmpty(), onClick = {
                val h = spec.time.take(2).toIntOrNull() ?: 9; val m = spec.time.drop(3).toIntOrNull() ?: 0
                TimePickerDialog(ctx, { _, hh, mm -> onChange(spec.copy(time = "%02d:%02d".format(hh, mm))) }, h, m, true).show()
            }) { Text(if (spec.time.isEmpty()) "時刻なし（終日）" else spec.time) }
            if (spec.time.isNotEmpty()) TextButton(onClick = { onChange(spec.copy(time = "")) }) { Text("消す") }
        }
        if (spec.due.isEmpty()) Text("日付を選ぶと時刻を付けられます", style = MaterialTheme.typography.bodySmall)

        Heading("所要時間")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for ((label, m) in listOf("なし" to 0, "15 分" to 15, "30 分" to 30, "1 時間" to 60, "2 時間" to 120)) Chip(label, spec.duration == m) { onChange(spec.copy(duration = m)) }
        }

        Heading("通知")
        // 何も選んでいない既定は「時刻があれば時刻ちょうど」。時刻がなければ朝のまとめだけ(通知を選んだときだけ 9 時を基準に知らせる)
        val offsets: Set<Int> = when {
            spec.reminds == "none" -> emptySet()
            spec.reminds.isEmpty() -> if (spec.time.isEmpty()) emptySet() else setOf(0)
            else -> Agenda.parseReminds(spec.reminds)?.toSet() ?: emptySet()
        }
        fun setOffsets(s: Set<Int>) = onChange(spec.copy(reminds = when { s.isEmpty() -> "none"; s == setOf(0) && spec.time.isNotEmpty() -> ""; else -> Agenda.remindsText(s.toList()) }))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for ((label, m) in listOf("時刻ちょうど" to 0, "5 分前" to 5, "10 分前" to 10, "30 分前" to 30, "1 時間前" to 60, "1 日前" to 1440))
                Chip(label, m in offsets) { setOffsets(if (m in offsets) offsets - m else offsets + m) }
            Chip("通知しない", spec.reminds == "none") { onChange(spec.copy(reminds = if (spec.reminds == "none") "" else "none")) }
        }
        if (spec.time.isEmpty()) Text("時刻がないタスクは、朝のまとめでお知らせします。通知を選ぶと、その日の 9 時を基準に知らせます", style = MaterialTheme.typography.bodySmall)

        Heading("繰り返し")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for ((label, v) in listOf("なし" to "", "毎日" to "daily", "毎週" to "weekly", "毎月" to "monthly", "毎年" to "yearly")) Chip(label, spec.repeat == v) { onChange(spec.copy(repeat = v)) }
        }
        if (spec.repeat.isNotEmpty() && spec.due.isEmpty()) Text("繰り返しは日付があるタスクで次の回に使われます", style = MaterialTheme.typography.bodySmall)

        Heading("優先度")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for ((label, v) in listOf("なし" to "", "低" to "low", "中" to "medium", "高" to "high")) Chip(label, spec.priority == v) { onChange(spec.copy(priority = v)) }
        }
    }
}
