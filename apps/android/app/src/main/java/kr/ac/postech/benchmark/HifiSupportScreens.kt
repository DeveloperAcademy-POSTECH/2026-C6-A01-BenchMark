package kr.ac.postech.benchmark

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import java.time.ZoneOffset

val supportSteps = listOf("약관 동의 및 본인 인증", "약정 내역 선택 및 입력", "기부자 구분 선택",
    "기부자 인적사항 작성", "스토리 작성 및 이미지 첨부")

@Composable
fun HifiSupportIntro(next: () -> Unit) = OiFormPage(0, "후원 시작") {
    Text("누군가의 기억이\n다른 누군가의\n쉼이 될 수 있도록.", fontSize = 28.sp, lineHeight = 38.sp)
    Text("기억이 남는 장소에는 늘 사람이 있습니다.\n잠시 앉아 나눈 대화, 함께 보낸 오후...\n그리고 오래 남은 마음.", fontSize = 14.sp, lineHeight = 22.sp)
    Text("벤치마크는 그 마음을 기부와 연결하고,\n함께 머무를 수 있는 공간으로 이어가는 방법을 찾습니다.", fontSize = 14.sp, lineHeight = 22.sp)
    Text("우리가 이어가려는 것", fontSize = 22.sp)
    listOf(
        Triple("01 _ MEMORY", "장소를 기억하는\n사람들의 마음", "마음이 머물렀던 장소에서 출발합니다. 어떤 장소가 나에게 소중해진 순간에서 시작합니다."),
        Triple("02 _ CONNECTION", "마음을 전하는\n구체적인 방법", "기부와 공간을 잇는 참여 방식을 고민합니다. 많은 뜻이 실제 공간과 연결되도록, 참여하는 사람과 공간을 운영하는 사람 사이의 과정을 고민합니다."),
        Triple("03 _ CONTINUITY", "만드는 순간부터\n그다음의 시간까지", "다음 사람이 누를 쉼과 그 이후를 생각합니다. 의미가 이어질 수 있도록 진행 과정과 이후의 돌봄까지 함께 생각합니다.")
    ).forEachIndexed { index, (label, title, body) ->
        Column(Modifier.fillMaxWidth(.65f).align(if (index == 1) Alignment.End else Alignment.Start)
            .drawBehind { drawLine(Color(0xFFD3DBC4), Offset.Zero, Offset(0f, size.height), 1.dp.toPx()) }.padding(start = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(label, fontSize = 10.sp); Text(title, fontSize = 20.sp, lineHeight = 30.sp)
            Text(body, fontSize = 8.sp, lineHeight = 12.sp)
        }
    }
    OiNotice("기존 벤치에 이야기 명패를 연결합니다. 실제 약정·납입·영수증은 학교의 공식 절차에서 처리합니다.")
    OiButton("기부 시작하기", "next", onClick = next)
}

@Composable
fun HifiStepOverview(next: () -> Unit) = Page {
    supportSteps.forEachIndexed { index, title ->
        Row(Modifier.fillMaxWidth().background(OiColors.Soft, RoundedCornerShape(15.dp)), verticalAlignment = Alignment.CenterVertically) {
            Text("STEP %02d".format(index + 1), color = OiColors.Soft, fontSize = 18.sp,
                modifier = Modifier.background(OiColors.Green, RoundedCornerShape(15.dp)).padding(8.dp))
            Text(title, Modifier.weight(1f).padding(12.dp), fontSize = 16.sp)
        }
    }
    Spacer(Modifier.height(160.dp))
    OiNotice("다음 화면은 로컬 신청·디자인 확인용입니다. 학교 약정·본인인증·실제 결제는 연결하지 않습니다.")
    OiButton("다음", "next", onClick = next)
}

@Composable
fun HifiTerms(state: LofiState, update: ((LofiState) -> LofiState) -> Unit, next: () -> Unit) = OiFormPage(1, supportSteps[0]) {
    OiNotice("디자인 약관 예시입니다. 실제 동의·신청으로 전송하지 않습니다. 학교의 약관과 개인정보 처리는 공식 기부 절차에서 확인합니다.")
    val titles = listOf("[필수] 개인정보 수집 동의", "[선택] 영수증 발급 동의", "[선택] 기부자 예우 동의", "[선택] 제3자 제공 동의")
    val states = listOf(state.requiredTerms, state.receiptTerms, state.honorTerms, state.thirdPartyTerms)
    val descriptions = listOf(
        "발전기금 기부 약정을 위한 개인정보 수집 동의\n\n1. 개인정보 수집 및 이용 목적\n기부 약정 업무, 수납 처리, 기부자 예우와 관련한 행정 업무를 위한 내용입니다.",
        "기부금 영수증 발급을 위한 개인정보 수집 동의\n\n1. 개인정보 수집 및 이용 목적\n학교의 기부금 영수증 발급 절차에서 안내합니다. 고유식별정보는 이 앱에서 입력하지 않습니다.",
        "기부자 예우를 위한 개인정보 수집 동의\n\n학교의 예우 프로그램과 선택 정보 처리 범위를 공식 절차에서 확인합니다.",
        "세제혜택 및 기부금 납부를 위한 개인정보 제3자 제공 동의\n\n제공 대상과 항목·이용 기간은 학교 공식 절차에서 확인합니다. 앱이 계좌·카드 정보를 수집하지 않습니다."
    )
    titles.forEachIndexed { index, title ->
        Text(descriptions[index].substringBefore("\n"), fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        Text(descriptions[index], fontSize = 12.sp, lineHeight = 16.sp,
            modifier = Modifier.fillMaxWidth().height(145.dp).border(1.dp, Color(0xFFD3DBC4))
                .verticalScroll(rememberScrollState()).padding(10.dp))
        Box(Modifier.background(OiColors.Soft, RoundedCornerShape(10.dp))) {
            Check(title, states[index]) { checked -> update {
                when (index) { 0 -> it.copy(requiredTerms = checked); 1 -> it.copy(receiptTerms = checked)
                    2 -> it.copy(honorTerms = checked); else -> it.copy(thirdPartyTerms = checked) }
            } }
        }
    }
    OiButton("본인인증 예시로", "next", state.requiredTerms, next)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HifiAmount(state: LofiState, update: ((LofiState) -> LofiState) -> Unit, next: () -> Unit) = OiFormPage(2, supportSteps[1]) {
    var showDate by remember { mutableStateOf(false) }
    OiInput("기부 금액 (디자인 예시 · 최소 5만원)", state.amount, "amount", "금액입력", keyboard = KeyboardType.Number,
        error = if (state.amount.isNotEmpty() && !validAmount(state.amount)) "예시 입력은 5만원 이상으로 확인해 주세요." else null) { value ->
        update { it.copy(amount = value.filter { char -> char in '0'..'9' }.take(12)) }
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        listOf(10000L, 50000L, 100000L, 200000L).forEach { amount ->
            TextButton({ update { it.copy(amount = ((it.amount.toLongOrNull() ?: 0) + amount).coerceAtMost(999_999_999_999).toString()) } },
                Modifier.weight(1f), contentPadding = PaddingValues(0.dp)) { Text("+${amount / 10000}만원", fontSize = 12.sp) }
        }
    }
    TextButton({ update { it.copy(amount = "50000") } }, Modifier.testTag("fill-amount")) { Text("5만원 입력") }
    Text("기부 예정일", fontWeight = FontWeight.SemiBold)
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(state.pledgeDate.ifBlank { "예정일 미선택" }, Modifier.background(OiColors.Shortcut, RoundedCornerShape(30.dp)).padding(10.dp))
        TextButton({ showDate = true }) { Text("변경") }
    }
    if (showDate) {
        val picker = rememberDatePickerState()
        DatePickerDialog(onDismissRequest = { showDate = false },
            confirmButton = { TextButton({
                picker.selectedDateMillis?.let { millis -> update { it.copy(pledgeDate = Instant.ofEpochMilli(millis).atOffset(ZoneOffset.UTC).toLocalDate().toString()) } }
                showDate = false
            }, enabled = picker.selectedDateMillis != null) { Text("선택") } },
            dismissButton = { TextButton({ showDate = false }) { Text("취소") } }) { DatePicker(picker) }
    }
    Text("결제 방법", fontWeight = FontWeight.SemiBold)
    listOf("무통장입금 (계좌이체)", "온라인결제 (신용카드/체크카드)", "간편결제 (카카오뱅크/토스뱅크 등)").forEach { label ->
        Row(Modifier.fillMaxWidth().background(OiColors.Soft, RoundedCornerShape(10.dp)).padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            RadioButton(false, null, enabled = false); Text(label, fontSize = 14.sp)
        }
    }
    OiNotice("결제 수단은 디자인 안내입니다. 금액·예정일은 로컬 신청 예시이며 운영 기준이 아닙니다. 실제 약정과 납입은 학교의 공식 절차에서 진행합니다.")
    OiButton("다음", "next", validAmount(state.amount), next)
}

@Composable
fun HifiCategory(donor: Donor, change: (Donor) -> Unit, next: () -> Unit) = OiFormPage(3, supportSteps[2]) {
    donorCategories.chunked(2).forEach { row ->
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            row.forEach { category ->
                Button({ change(donor.copy(category = category)) }, Modifier.weight(1f).heightIn(min = 80.dp),
                    shape = RoundedCornerShape(10.dp), colors = ButtonDefaults.buttonColors(
                        containerColor = if (donor.category == category) OiColors.Green else Color(0xFFEAEEE2),
                        contentColor = if (donor.category == category) OiColors.Soft else OiColors.Green)) { Text(category, fontSize = 26.sp) }
            }
            if (row.size == 1) Spacer(Modifier.weight(1f))
        }
    }
    OiButton("다음", "next", onClick = next)
}

@Composable
fun HifiDonor(donor: Donor, change: (Donor) -> Unit, next: () -> Unit, skip: (() -> Unit)? = null) = OiFormPage(4, supportSteps[3]) {
    OiInput("성명 (법인명 / 단체명) · 이야기 작성자", donor.name, "donor-name", "공개할 이름 또는 별명") { change(donor.copy(name = boundedText(it, 50))) }
    OiInput("주민(사업자)등록번호", "", "donor-identity", "학교 공식 절차에서 입력", enabled = false) {}
    OiInput("연락처(휴대전화)", "", "donor-phone", "학교 공식 절차에서 입력", enabled = false) {}
    OiInput("이메일", "", "donor-email", "학교 공식 절차에서 입력", enabled = false) {}
    OiNotice("고유식별정보·연락처·학교 학적 정보를 중복 수집하지 않습니다. 실제 세제혜택과 영수증 정보는 학교 공식 절차에서 입력합니다. 이 화면의 이름은 로컬 이야기 작성자 예시입니다.")
    OiButton("다음", "next", onClick = next)
    if (skip != null) TextButton(skip) { Text("건너뛰기") }
}

fun boundedText(value: String, maxCodePoints: Int): String {
    val length = value.codePointCount(0, value.length)
    return if (length <= maxCodePoints) value else value.substring(0, value.offsetByCodePoints(0, maxCodePoints))
}
