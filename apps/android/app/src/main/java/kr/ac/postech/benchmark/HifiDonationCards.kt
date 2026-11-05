package kr.ac.postech.benchmark

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

fun storyImage(photo: Int): Int? = when (photo) {
    1 -> R.drawable.story_campus; 2 -> R.drawable.story_birthday; 3 -> R.drawable.story_view
    4 -> R.drawable.story_lake; 5 -> R.drawable.story_sea; else -> null
}

fun sortedDonations(state: LofiState): List<Donation> = when (state.donationSort) {
    "오래된순" -> state.donations.sortedWith(compareBy<Donation> { it.createdDate }.thenBy { it.id })
    "좋아요순" -> state.donations.sortedWith(compareByDescending<Donation> { it.reactions }.thenByDescending { it.createdDate }.thenByDescending { it.id })
    else -> state.donations.sortedWith(compareByDescending<Donation> { it.createdDate }.thenByDescending { it.id })
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun HifiMyDonations(state: LofiState, update: ((LofiState) -> LofiState) -> Unit, select: (Int) -> Unit,
                    donate: () -> Unit, sample: () -> Unit, like: (Int) -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("최신순", "오래된순", "좋아요순").forEach { sort ->
                TextButton({ update { it.copy(donationSort = sort) } },
                    colors = ButtonDefaults.textButtonColors(
                        containerColor = if (state.donationSort == sort) Color(0xFF9EB452) else OiColors.Shortcut,
                        contentColor = if (state.donationSort == sort) Color(0xFFF7FAEF) else OiColors.Dark),
                    shape = RoundedCornerShape(30.dp), contentPadding = PaddingValues(horizontal = 10.dp)) { Text(sort, fontSize = 14.sp) }
            }
            Row(Modifier.background(Color(0xFFEAEEE2), RoundedCornerShape(30.dp))) {
                IconButton({ update { it.copy(gridDonations = false) } }, Modifier.testTag("single-layout").semantics { selected = !state.gridDonations }) {
                    Icon(Icons.AutoMirrored.Filled.List, "단일 카드 보기", tint = OiColors.Green)
                }
                IconButton({ update { it.copy(gridDonations = true) } }, Modifier.testTag("grid-layout").semantics { selected = state.gridDonations }) {
                    Icon(painterResource(R.drawable.ic_grid), "2열 모아보기", tint = OiColors.Green)
                }
            }
        }
        Text("디자인·로컬 신청 예시 · 학교 납입 확인 미연결", fontSize = 12.sp, color = OiColors.Dark)
        if (state.donations.isEmpty()) {
            Text("아직 기부 내역이 없습니다", fontSize = 22.sp)
            Text("오래 남는 이야기를 캠퍼스에 남겨보세요.")
            OiButton("기부 참여해보시겠습니까?", onClick = donate)
            OutlinedButton(sample, Modifier.fillMaxWidth()) { Text("기부 내역 예시 불러오기") }
        } else {
            val records = sortedDonations(state)
            if (state.gridDonations) records.chunked(2).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    row.forEach { record -> DonationStoryCard(record, true, Modifier.weight(1f), { select(record.id) }, { like(record.id) }) }
                    if (row.size == 1) Spacer(Modifier.weight(1f))
                }
            } else records.forEach { record -> DonationStoryCard(record, false, Modifier.fillMaxWidth(), { select(record.id) }, { like(record.id) }) }
            OiButton("다음 시즌 기부하기", onClick = donate)
        }
    }
}

@Composable
fun DonationStoryCard(donation: Donation, mini: Boolean, modifier: Modifier = Modifier,
                      open: (() -> Unit)? = null, like: (() -> Unit)? = null) {
    var flipped by rememberSaveable(donation.id) { mutableStateOf(false) }
    BoxWithConstraints(modifier.aspectRatio(362f / 502f).shadow(6.dp, RoundedCornerShape(30.dp)).clip(RoundedCornerShape(30.dp)).background(OiColors.Light)
        .testTag("donation-card-${donation.id}").then(if (open != null) Modifier.clickable(role = Role.Button, onClick = open) else Modifier)) {
        if (flipped) {
            Image(painterResource(R.drawable.story_map), "Figma 캠퍼스 지도 예시", Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alpha = .62f)
            Column(Modifier.align(Alignment.Center).padding(if (mini) 8.dp else 16.dp).background(OiColors.Light, RoundedCornerShape(15.dp)).padding(if (mini) 8.dp else 12.dp)) {
                Text(if (mini) "벤치 ${donation.bench}" else "벤치 ${donation.bench} · 지도 예시", fontSize = if (mini) 14.sp else 20.sp)
                Text(if (mini) "학교 확인 대기" else "학교 확인 대기\n${installationStages[donation.stage.coerceIn(installationStages.indices)]}\n진행 상태는 로컬 예시입니다.", fontSize = 12.sp)
            }
        } else {
            storyImage(donation.story.photo)?.let { image ->
                Image(painterResource(if (donation.story.photo == 1 && !mini) R.drawable.story_card_background else image),
                    null, Modifier.fillMaxSize().then(if (donation.story.photo == 1 && !mini) Modifier.blur(9.dp) else Modifier), contentScale = ContentScale.Crop)
                Box(Modifier.matchParentSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color(0xFF323F1D).copy(alpha = .8f)))))
                if (donation.story.photo == 1 && !mini) {
                    val scale = maxWidth / 362.dp
                    val benchY = minOf(272.dp * scale, (maxHeight - 75.dp * scale - 155.dp).coerceAtLeast(0.dp))
                    Image(painterResource(R.drawable.story_bench_shadow), null,
                        Modifier.size(238.dp * scale, 86.dp * scale).align(Alignment.TopCenter).offset(y = benchY + 20.dp * scale), contentScale = ContentScale.FillBounds)
                    Image(painterResource(R.drawable.story_bench), null,
                        Modifier.size(132.dp * scale, 75.dp * scale).align(Alignment.TopCenter).offset(y = benchY), contentScale = ContentScale.FillBounds)
                }
            }
            Column(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(if (mini) 16.dp else 25.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val foreground = if (storyImage(donation.story.photo) == null) OiColors.Dark else OiColors.Soft
                Text(donation.createdDate.ifBlank { "날짜 미기록" }, color = foreground, fontSize = if (mini) 12.sp else 22.sp)
                Text(donation.story.title.ifBlank { "제목 없음" }, color = foreground, fontSize = if (mini) 16.sp else 17.sp,
                    modifier = if (open != null) Modifier.clickable(role = Role.Button, onClick = open) else Modifier)
                if (!mini) {
                    HorizontalDivider(color = foreground.copy(alpha = .6f))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        if (like != null) TextButton(like, Modifier.testTag("like-${donation.id}"), contentPadding = PaddingValues(0.dp)) {
                            Text("${if (donation.liked) "♥" else "♡"} 좋아요 ${donation.reactions}", color = foreground, fontSize = 12.sp)
                        }
                        Text("로컬 예시", color = foreground, fontSize = 12.sp)
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(if (mini) 12.dp else 15.dp), horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically) {
            Text("예시", color = OiColors.Soft, fontSize = 12.sp,
                modifier = Modifier.background(OiColors.Green, RoundedCornerShape(20.dp)).padding(horizontal = 10.dp, vertical = 6.dp))
            TextButton({ flipped = !flipped }, Modifier.testTag("flip-${donation.id}"),
                colors = ButtonDefaults.textButtonColors(containerColor = OiColors.Light), contentPadding = PaddingValues(horizontal = 10.dp)) {
                Text(if (flipped) "접기" else if (mini) "뒤집기" else "펼치기", fontSize = 12.sp)
            }
        }
    }
}

@Composable
fun HifiStory(story: Story, change: (Story) -> Unit, photo: () -> Unit, next: () -> Unit,
              editing: Boolean = false, cancel: (() -> Unit)? = null, preview: (() -> Unit)? = null) = OiFormPage(5, supportSteps[4]) {
    OiInput("제목 *", story.title, "story-title", "30자 이내") { change(story.copy(title = boundedText(it, 30))) }
    OiInput("내용 입력 *", story.body, "story-body", "500자 이내", multiline = true) { change(story.copy(body = boundedText(it, 500))) }
    Text("이미지 첨부 (미리보기)", fontSize = 16.sp)
    if (storyImage(story.photo) != null) DonationStoryCard(Donation(0, 1, "", story), false)
    else OiNotice("선택한 이미지가 없습니다. 사진 없이도 로컬 신청 예시를 확인할 수 있습니다.")
    OutlinedButton(photo, Modifier.fillMaxWidth().testTag("edit-photo")) { Text("이미지 선택 / 변경") }
    OiNotice("로컬 이야기 예시입니다. 서버에 저장하거나 실제 참여 신청을 전송하지 않습니다.")
    if (preview != null) OiButton("미리보기", onClick = preview)
    OiButton(if (editing) "저장" else "다음", if (editing) "save-edit" else "next",
        story.title.isNotBlank() && story.body.isNotBlank(), next)
    if (cancel != null) TextButton(cancel) { Text("취소") }
}

@Composable
fun HifiReceipt(donations: () -> Unit, home: () -> Unit) = Page {
    Spacer(Modifier.height(100.dp))
    Text("참여 신청\n예시 확인", color = OiColors.Green, fontSize = 48.sp, lineHeight = 60.sp)
    OiNotice("로컬 예시 내역을 추가했습니다. 실제 신청·약정·납입은 처리하지 않았습니다. 학교 확인 전에는 기부 확인 대기입니다.")
    OiButton("나의 기부 보기", onClick = donations)
    OiButton("홈으로", onClick = home)
}
