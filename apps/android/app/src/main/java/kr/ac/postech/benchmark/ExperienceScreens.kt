package kr.ac.postech.benchmark

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun VerificationScreen(next: () -> Unit) = Page {
    var provider by rememberSaveable { mutableStateOf("SKT") }
    var failed by rememberSaveable { mutableStateOf(false) }
    Heading("휴대폰 본인인증")
    Text("통신사 선택 화면 예시")
    listOf("SKT", "KT", "LG U+", "알뜰폰").forEach { item ->
        FilterChip(provider == item, { provider = item }, { Text(item) })
    }
    if (failed) Text("인증 실패 예시입니다. 다시 진행하거나 뒤로 돌아갈 수 있습니다.")
    Action("인증 완료 화면으로 계속", "verify", onClick = next)
    OutlinedButton({ failed = true }, Modifier.fillMaxWidth()) { Text("인증 실패 예시 보기") }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ReactionButtons(selected: String, select: (String) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf("좋아요", "공감해요", "슬퍼요", "응원해요").forEach { label ->
            FilterChip(selected == label, { select(if (selected == label) "" else label) }, { Text(label) })
        }
    }
}

@Composable
fun ArScreen() = Page {
    val context = androidx.compose.ui.platform.LocalContext.current
    Heading("캐릭터와 함께 촬영하기")
    Text("카메라로 바닥을 인식한 뒤 캐릭터를 배치하고 사진이나 음성 포함 영상을 촬영합니다.")
    Text("ARCore 지원 기기가 필요합니다. 물체 가림은 Depth 지원 기기에서 제공됩니다.")
    Action("AR 카메라 시작", "start-ar") {
        context.startActivity(android.content.Intent(context, kr.ac.postech.benchmark.ar.ArCameraActivity::class.java))
    }
}
