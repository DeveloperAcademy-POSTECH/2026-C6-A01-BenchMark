package kr.ac.postech.benchmark

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp

@Composable
fun LoginScreen(next: () -> Unit) = Page {
    var username by rememberSaveable { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    Block("BenchMark", 100)
    Field("아이디 (예시)", username, "login-name") { username = it }
    OutlinedTextField(password, { password = it }, Modifier.fillMaxWidth(),
        label = { Text("비밀번호 (예시)") }, singleLine = true,
        visualTransformation = PasswordVisualTransformation())
    Action("로그인 예시로 시작", "login", onClick = next)
    Text("SNS 로그인 영역")
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
        for (index in 1..3) OutlinedButton(next) { Text("SNS $index") }
    }
}

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
fun ArScreen(capture: () -> Unit) = Page {
    var permissionStep by rememberSaveable { mutableIntStateOf(-1) }
    var ready by rememberSaveable { mutableStateOf(false) }
    var denied by rememberSaveable { mutableStateOf(false) }
    val permissions = listOf("카메라", "사진", "위치")
    Block("AR 미리보기 영역", 280)
    Text("실제 카메라·AR·위치 기능은 연결하지 않았습니다.")
    if (denied) Text("권한 거부 예시 · 체험을 다시 시작하거나 이전 화면으로 돌아갈 수 있습니다.")
    if (ready) {
        Action("촬영 결과 예시 보기", "capture", onClick = capture)
    } else {
        Action("AR 체험 시작", "start-ar") { permissionStep = 0; denied = false }
    }
    if (permissionStep in permissions.indices) {
        AlertDialog(
            onDismissRequest = { permissionStep = -1; denied = true },
            title = { Text("${permissions[permissionStep]} 권한 (예시)") },
            text = { Text("lo-fi의 권한 분기를 확인합니다. 시스템 권한은 요청하지 않습니다.") },
            confirmButton = { TextButton({
                if (permissionStep == permissions.lastIndex) { ready = true; permissionStep = -1 }
                else permissionStep++
            }) { Text("허용 예시") } },
            dismissButton = { TextButton({ permissionStep = -1; denied = true }) { Text("허용 안 함") } }
        )
    }
}

@Composable
fun CaptureScreen(back: () -> Unit) = Page {
    var saved by rememberSaveable { mutableStateOf(false) }
    Block("사진 촬영 결과 영역", 300)
    if (saved) Text("저장 완료 화면 예시입니다. 실제 사진 파일은 생성하지 않았습니다.")
    Action("저장 결과 예시 보기") { saved = true }
    Action("다시 촬영", onClick = back)
}
