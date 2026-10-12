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
fun TermsScreen(state: LofiState, update: ((LofiState) -> LofiState) -> Unit, next: () -> Unit) = Page {
    Heading("온라인 약정 동의")
    Text("실제 약정이 아닌 화면 이동용 동의 예시입니다.")
    Check("전체 동의", state.requiredTerms && state.receiptTerms) { checked ->
        update { it.copy(requiredTerms = checked, receiptTerms = checked) }
    }
    Block("[필수] 발전기금 기부 약정을 위한 개인정보 수집 동의\n약관 내용 영역", 120)
    Check("[필수] 개인정보 수집 동의", state.requiredTerms) { checked -> update { it.copy(requiredTerms = checked) } }
    Block("[선택] 기부금 영수증 발급을 위한 개인정보 수집 동의\n약관 내용 영역", 120)
    Check("[선택] 영수증 발급 동의", state.receiptTerms) { checked -> update { it.copy(receiptTerms = checked) } }
    Action("본인인증으로", "next", state.requiredTerms, next)
}

@Composable
fun AmountScreen(amount: String, change: (String) -> Unit, next: () -> Unit) = Page {
    Text("1 / 4 · 기부금")
    Text("최소금액 : 100만원 (lo-fi 기준)")
    Field("기부금 (원)", amount, "amount", KeyboardType.Number) { input ->
        change(input.filter(Char::isDigit).take(12))
    }
    if (amount.isNotEmpty() && !validAmount(amount)) Text("100만원 이상 입력해주세요.", color = MaterialTheme.colorScheme.error)
    Action("100만원 입력", "fill-amount") { change("1000000") }
    Action("다음", "next", validAmount(amount), next)
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
fun MyDonationsScreen(state: LofiState, select: (Int) -> Unit, donate: () -> Unit, sample: () -> Unit) = Page {
    if (state.donations.isEmpty()) {
        Heading("아직 기부 내역이 없습니다")
        DonationGuide()
        Action("기부 참여해보시겠습니까?", onClick = donate)
        OutlinedButton(sample, Modifier.fillMaxWidth()) { Text("기부 내역 예시 불러오기") }
    } else {
        state.donations.forEach { donation ->
            OutlinedCard({ select(donation.id) }, Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("벤치 ${donation.bench} · ${donation.amount}원")
                    Text(donation.story.title.ifBlank { "제목 없음" })
                    Text("진행 사항 · ${installationStages[donation.stage]} (예시)")
                }
            }
        }
        Action("다른 벤치 기부하기", onClick = donate)
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
                StoryContent(donation.story)
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
