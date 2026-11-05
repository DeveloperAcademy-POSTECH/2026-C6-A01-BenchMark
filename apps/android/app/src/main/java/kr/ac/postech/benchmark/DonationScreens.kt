package kr.ac.postech.benchmark

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp

@Composable
fun BenchScreen(selected: Int, select: (Int) -> Unit, next: () -> Unit) = Page {
    Heading("벤치 위치 & 기부 가능 벤치")
    Block("캠퍼스 지도 영역\n아래 위치를 선택해보세요", 200)
    for (index in 1..4) {
        OutlinedButton({ select(index) }, Modifier.fillMaxWidth(), enabled = index != 4) {
            Text("${if (selected == index) "✓ " else ""}벤치 $index · ${if (index == 4) "기부 완료" else "기부 가능"}")
        }
    }
    Action("선택한 벤치 확인", "select-bench", onClick = next)
}

@Composable
fun PhotoScreen(editing: Boolean, state: LofiState, update: ((LofiState) -> LofiState) -> Unit, done: () -> Unit) = Page {
    var permission by rememberSaveable { mutableStateOf(false) }
    var denied by rememberSaveable { mutableStateOf(false) }
    val story = if (editing) state.editDraft else state.draft
    if (!permission) {
        Heading("사진 접근 권한 안내")
        Text("권한 분기 화면 예시입니다. 실제 사진 보관함에는 접근하지 않습니다.")
        if (denied) Text("사진 없이 계속하거나 권한 허용 예시를 다시 선택할 수 있습니다.")
        Action("허용 예시", "allow-photo") { permission = true; denied = false }
        Action("허용 안 함 예시", "deny-photo") { denied = true }
        Action("사진 없이 돌아가기", onClick = done)
    } else {
        Heading("예시 이미지 선택")
        for (number in 1..2) {
            Action("${if (story.photo == number) "✓ " else ""}예시 이미지 $number", "photo-$number") {
                update { if (editing) it.copy(editDraft = it.editDraft.copy(photo = number)) else it.copy(draft = it.draft.copy(photo = number)) }
            }
        }
        Action("이미지 제거") { update { if (editing) it.copy(editDraft = it.editDraft.copy(photo = 0)) else it.copy(draft = it.draft.copy(photo = 0)) } }
        Action("선택 완료", "photo-done", onClick = done)
    }
}

@Composable
fun DonationScreen(screen: Screen, donation: Donation?, edit: () -> Unit, preview: () -> Unit,
                   progress: () -> Unit, installed: () -> Unit, setStage: (Int) -> Unit) = Page {
    if (donation == null) {
        Text("선택한 기부 내역이 없습니다.")
    } else {
        when (screen) {
            Screen.DONATION -> {
                Text("진행 사항 · ${installationStages[donation.stage]}")
                LinearProgressIndicator(progress = { (donation.stage + 1) / 6f }, modifier = Modifier.fillMaxWidth())
                DonationStoryCard(donation, false)
                Text(donation.story.body)
                Text("벤치 ${donation.bench} · ${donation.amount}원")
                Action("이야기 / 문구 / 사진 편집", "open-edit", onClick = edit)
                Action("미리보기", onClick = preview)
                Action("설치 프로세스 확인", onClick = progress)
            }
            Screen.PROGRESS -> {
                Heading("설치 진행 사항")
                installationStages.forEachIndexed { index, label ->
                    Text("${if (index <= donation.stage) "●" else "○"} $label")
                }
                Text("각 단계를 눌러보는 대신 아래 버튼으로 다음 상태를 확인합니다. 실제 설치 상태가 아닙니다.")
                if (donation.stage < installationStages.lastIndex) {
                    Action("다음 단계 예시", "advance-stage") { setStage(donation.stage + 1) }
                } else {
                    Action("설치된 벤치 보기", onClick = installed)
                }
            }
            else -> {
                Block("설치된 벤치 이미지 / 3D 영역", 200)
                Text("캠퍼스 위치 ${donation.bench} · ${donation.amount}원")
                StoryContent(donation.story)
                var reaction by rememberSaveable { mutableStateOf("") }
                ReactionButtons(reaction) { reaction = it }
            }
        }
    }
}
