package kr.ac.postech.benchmark.ar

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.util.Locale

@Composable
fun ArControls(controller: ArController) {
    val settings = controller.settings
    val enabled = !controller.busy && !controller.loading
    var menu by remember { mutableStateOf(false) }
    var expanded by rememberSaveable { mutableStateOf(false) }
    Box {
        OutlinedButton({ menu = true }, enabled = enabled) { Text("캐릭터: ${settings.character.title}") }
        DropdownMenu(menu, { menu = false }) {
            ArCharacter.entries.forEach { character ->
                DropdownMenuItem(text = { Text(character.title) }, onClick = {
                    menu = false; controller.update(settings.copy(character = character))
                })
            }
        }
    }
    if (controller.motions.isNotEmpty()) {
        controller.motions.forEachIndexed { index, title ->
            FilterChip(controller.motion == index, { controller.selectMotion(index) }, { Text(title) }, enabled = enabled)
        }
        TextButton({ controller.toggleMotion() }, enabled = enabled && controller.motion >= 0) {
            Text(if (controller.playing) "동작 일시정지" else "동작 계속 재생")
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        FilterChip(controller.locked, { controller.locked = !controller.locked }, { Text("위치 잠금") }, enabled = enabled && controller.placed)
        TextButton({ controller.resetPlacement() }, enabled = enabled && controller.placed) { Text("배치 초기화") }
        TextButton({ expanded = !expanded }) { Text(if (expanded) "조절 닫기" else "배치·조명 조절") }
    }
    if (expanded) {
        Adjustment("키", settings.height, 0.1f..3f, "m", enabled) { controller.update(settings.copy(height = it)) }
        Adjustment("회전", settings.rotation, -180f..180f, "°", enabled) { controller.update(settings.copy(rotation = it)) }
        Adjustment("바닥 높이", settings.floorOffset, -0.5f..0.5f, "m", enabled) { controller.update(settings.copy(floorOffset = it)) }
        Toggle("주변 조명 반영", settings.environment, enabled) { controller.update(settings.copy(environment = it)) }
        Adjustment("환경 밝기 보정", settings.exposure, -2f..2f, "EV", enabled && settings.environment) { controller.update(settings.copy(exposure = it)) }
        Toggle("바닥 그림자", settings.shadows, enabled) { controller.update(settings.copy(shadows = it)) }
        Toggle("실제 물체에 가려짐 (Depth)", settings.depth && controller.depthSupported, enabled && controller.depthSupported) {
            controller.update(settings.copy(depth = it))
        }
        if (!controller.depthSupported) Text("이 기기는 Depth 가림을 지원하지 않습니다.", style = MaterialTheme.typography.bodySmall)
        Toggle("수동 보조 조명", settings.directLight, enabled) { controller.update(settings.copy(directLight = it)) }
        if (settings.directLight) {
            Adjustment("광원 강도", settings.intensity, 0f..100_000f, "lux", enabled) { controller.update(settings.copy(intensity = it)) }
            Adjustment("광원 방위", settings.azimuth, -180f..180f, "°", enabled) { controller.update(settings.copy(azimuth = it)) }
            Adjustment("광원 고도", settings.elevation, 5f..90f, "°", enabled) { controller.update(settings.copy(elevation = it)) }
        }
        Text("광원 방향은 AR 공간 기준입니다. 실제 나침반·태양 방향이 아닙니다.", style = MaterialTheme.typography.bodySmall)
        TextButton({ controller.update(ArSettings(character = settings.character)) }, enabled = enabled) { Text("배치·조명 기본값 복원") }
    }
}

@Composable
private fun Toggle(title: String, value: Boolean, enabled: Boolean, change: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(title, Modifier.weight(1f).padding(vertical = 12.dp))
        Switch(value, change, enabled = enabled)
    }
}

@Composable
private fun Adjustment(title: String, value: Float, range: ClosedFloatingPointRange<Float>, unit: String, enabled: Boolean, change: (Float) -> Unit) {
    Text("$title: ${String.format(Locale.getDefault(), "%.2f", value)} $unit")
    Slider(value, change, enabled = enabled, valueRange = range)
}
