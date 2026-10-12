package kr.ac.postech.benchmark

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp

@Composable
fun Page(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp), content = content
    )
}

@Composable
fun Action(label: String, tag: String = label, enabled: Boolean = true, onClick: () -> Unit) {
    Button(onClick, Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag(tag), enabled = enabled) {
        Text(label)
    }
}

@Composable
fun Block(label: String, height: Int = 160) {
    Box(
        Modifier.fillMaxWidth().heightIn(min = height.dp).background(MaterialTheme.colorScheme.surfaceVariant).padding(20.dp),
        contentAlignment = Alignment.Center
    ) { Text(label) }
}

@Composable
fun Heading(text: String) { Text(text, style = MaterialTheme.typography.headlineSmall) }

@Composable
fun Field(label: String, value: String, tag: String, type: KeyboardType = KeyboardType.Text,
          multiline: Boolean = false, onChange: (String) -> Unit) {
    OutlinedTextField(
        value, onChange, Modifier.fillMaxWidth().testTag(tag), label = { Text(label) },
        keyboardOptions = KeyboardOptions(keyboardType = type),
        singleLine = !multiline, minLines = if (multiline) 5 else 1
    )
}

@Composable
fun Check(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp)
            .toggleable(checked, role = Role.Checkbox, onValueChange = onChange).padding(4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Checkbox(checked, onCheckedChange = null)
        Text(label, Modifier.padding(start = 8.dp))
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DonorFields(donor: Donor, onChange: (Donor) -> Unit) {
    Text("기부자 구분")
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        donorCategories.forEach { category ->
            FilterChip(donor.category == category, { onChange(donor.copy(category = category)) }, { Text(category) })
        }
    }
    Field("성명 (법인명 / 단체명)", donor.name, "donor-name") { onChange(donor.copy(name = it)) }
    Field("연락처", donor.phone, "donor-phone", KeyboardType.Phone) { onChange(donor.copy(phone = it)) }
    Field("이메일", donor.email, "donor-email", KeyboardType.Email) { onChange(donor.copy(email = it)) }
    Check("세제혜택 희망", donor.wantsReceipt) { onChange(donor.copy(wantsReceipt = it)) }
    if (donor.wantsReceipt) {
        OutlinedTextField("", {}, Modifier.fillMaxWidth(), enabled = false,
            label = { Text("주민(사업자)등록번호") }, supportingText = { Text("화면 예시 · 실제 정보는 입력하지 않습니다.") })
    }
}

@Composable
fun StoryFields(story: Story, onChange: (Story) -> Unit, photo: () -> Unit) {
    Block(if (story.photo == 0) "이미지" else "선택한 예시 이미지 ${story.photo}")
    OutlinedButton(photo, Modifier.fillMaxWidth().testTag("edit-photo")) { Text("이미지 선택 / 변경") }
    Field("제목 / 명패 문구", story.title, "story-title") { onChange(story.copy(title = it)) }
    Field("스토리 입력", story.body, "story-body", multiline = true) { onChange(story.copy(body = it)) }
}

@Composable
fun StoryContent(story: Story) {
    Block(if (story.photo == 0) "이미지 없음" else "예시 이미지 ${story.photo}")
    Heading(story.title.ifBlank { "제목 없음" })
    Text(story.body.ifBlank { "아직 작성한 이야기가 없습니다." })
}

@Composable
fun DonationGuide() {
    Heading("우리 벤치마크는")
    Text("캠퍼스의 기억을 벤치와 이야기로 남기는 서비스입니다.")
    Block("최소 기부금액 · 100만원\n명패 기한 · 3년\n발전기금 2.0 안내", 130)
    Text("lo-fi에 표기된 안내 예시입니다. 실제 기부 조건은 연동 단계에서 확정합니다.")
}
