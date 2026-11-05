package kr.ac.postech.benchmark

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.BiasAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun HifiHomeScreen(state: LofiState, benches: () -> Unit, donations: () -> Unit,
                   nfc: () -> Unit, profile: () -> Unit, notifications: () -> Unit) {
    var information by remember { mutableStateOf<String?>(null) }
    information?.let { title ->
        AlertDialog(onDismissRequest = { information = null }, title = { Text(title) },
            text = { Text(when (title) {
                "오이기부 소개" -> "POSTECH의 기존 벤치에 이야기 명패와 NFC를 연결합니다. 실제 기부는 학교의 공식 절차를 이용하며 앱이 직접 수납하지 않습니다."
                "기부금영수증" -> "영수증은 학교의 공식 기부 절차에서 발급됩니다. 앱의 로컬 예시 내역은 납입 증빙이 아닙니다."
                else -> "운영 안내가 아직 연결되지 않았습니다. 확정된 정보가 준비되면 안내합니다."
            }) }, confirmButton = { TextButton({ information = null }) { Text("확인") } })
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)
        .padding(top = 12.dp, bottom = 20.dp), verticalArrangement = Arrangement.spacedBy(17.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Image(painterResource(R.drawable.oi_logo), null, Modifier.size(38.dp, 34.dp))
            Spacer(Modifier.width(6.dp))
            Image(painterResource(R.drawable.oi_wordmark), "오이기부", Modifier.size(101.dp, 24.dp))
            Spacer(Modifier.weight(1f))
            HeaderAction(null, "알림", notifications)
            HeaderAction(Icons.Default.Person, "프로필", profile)
        }
        HomeBanner { information = "오이기부 소개" }
        Row(Modifier.fillMaxWidth().background(OiColors.Light, RoundedCornerShape(20.dp)).padding(21.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(17.dp)) {
                Row(Modifier.testTag("home-donations").semantics { contentDescription = "나의 기부 현황" }.clickable(onClick = donations), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Image(painterResource(R.drawable.oi_logo), null, Modifier.size(21.dp, 18.dp))
                    Text("${state.donor.name.ifBlank { "기부자" }}님의 기부 내역", color = OiColors.Olive, fontSize = 20.sp)
                }
                Text(if (state.donations.isEmpty()) "아직 기부 내역이 없어요\n기부자님의 이야기를 남겨보시겠어요?"
                    else "로컬 예시 내역 ${state.donations.size}건\n학교 납입 확인과 연결되지 않았습니다.", fontSize = 14.sp, lineHeight = 18.sp)
            }
            Box(Modifier.size(70.dp).clip(CircleShape).clickable(onClick = benches).testTag("home-donate"),
                contentAlignment = Alignment.Center) {
                Image(painterResource(R.drawable.home_donation_button), null, Modifier.fillMaxSize())
                Text("기부\n시작", color = OiColors.Green, fontSize = 14.sp)
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(15.dp)) {
            Shortcut(Icons.AutoMirrored.Filled.List, "기부금영수증", Modifier.weight(1f)) { information = "기부금영수증" }
            Shortcut(Icons.Default.Star, "이벤트/혜택", Modifier.weight(1f)) { information = "이벤트/혜택" }
            Shortcut(Icons.Default.Info, "오이 소식", Modifier.weight(1f)) { information = "오이 소식" }
            Shortcut(Icons.Default.Favorite, "정기후원", Modifier.weight(1f)) { information = "정기후원" }
        }
        HomeImpactUnavailable()
        Text("기부·학교 현황은 로컬 예시 · Google 로그인은 선택", fontSize = 12.sp)
        TextButton(benches) { Text("기부할 벤치 찾기") }
        TextButton(nfc) { Text("NFC 벤치 체험") }
    }
}

@Composable
private fun HeaderAction(icon: ImageVector?, label: String, onClick: () -> Unit) {
    IconButton(onClick, Modifier.size(48.dp)) {
        Box(contentAlignment = Alignment.Center) {
            Image(painterResource(R.drawable.home_profile_background), null, Modifier.size(38.dp))
            if (icon != null) Icon(icon, label, Modifier.size(18.dp), tint = OiColors.Dark)
            else Icon(painterResource(R.drawable.ic_notifications), label, Modifier.size(18.dp), tint = OiColors.Dark)
        }
    }
}

@Composable
private fun HomeBanner(details: () -> Unit) {
    Box(Modifier.fillMaxWidth().heightIn(min = 219.dp).clip(RoundedCornerShape(20.dp))) {
        // Figma's portrait image starts 279 units above the 362 x 219 banner.
        Image(painterResource(R.drawable.home_bench), null,
            Modifier.matchParentSize(), contentScale = ContentScale.Crop, alignment = BiasAlignment(0f, .72f))
        Box(Modifier.matchParentSize().background(Brush.verticalGradient(
            listOf(Color(0xFF2F3F18).copy(alpha = .7f), Color.Transparent))))
        Column(Modifier.fillMaxWidth().padding(24.dp).padding(top = 7.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("“오래도록 남는 이야기, 오이기부”", color = OiColors.Soft, fontSize = 19.sp, lineHeight = 24.sp)
            Text("학교의 내일에 보탠 마음, 캠퍼스에 이야기로 남아요.\n첫 기부로 기억하고 싶은 순간을 벤치에 남겨보세요.",
                color = OiColors.Soft, fontSize = 14.sp, lineHeight = 18.sp)
            Spacer(Modifier.height(32.dp))
            TextButton(details, colors = ButtonDefaults.textButtonColors(containerColor = OiColors.Light,
                contentColor = Color.Black), contentPadding = PaddingValues(horizontal = 10.dp)) {
                Text("자세히보기 →", fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun Shortcut(icon: ImageVector, title: String, modifier: Modifier, onClick: () -> Unit) {
    Column(modifier.heightIn(min = 79.dp).clip(RoundedCornerShape(10.dp)).background(OiColors.Shortcut)
        .clickable(onClick = onClick).padding(vertical = 14.dp, horizontal = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, Modifier.size(23.dp), tint = OiColors.Olive)
        Text(title, fontSize = 11.sp, color = OiColors.Olive)
    }
}

@Composable
private fun HomeImpactUnavailable() {
    Column(Modifier.fillMaxWidth().border(2.dp, OiColors.Accent, RoundedCornerShape(20.dp)).padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("POSTECH 오이", fontSize = 20.sp, color = OiColors.Dark,
            modifier = Modifier.background(OiColors.Accent, RoundedCornerShape(topStart = 20.dp, bottomEnd = 20.dp)).padding(8.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Image(painterResource(R.drawable.oi_cucumber), null, Modifier.weight(1f).height(125.dp), contentScale = ContentScale.Fit)
            Column(Modifier.weight(1.4f).background(OiColors.Soft, RoundedCornerShape(20.dp)).padding(14.dp)) {
                Text("설치된 벤치 수", fontSize = 12.sp)
                Text("— / —", fontSize = 36.sp, color = OiColors.Green)
                Image(painterResource(R.drawable.home_divider), null, Modifier.fillMaxWidth().height(1.dp))
                Text("누적 참여자 수", fontSize = 12.sp)
                Text("— 명", fontSize = 36.sp, color = OiColors.Green)
            }
        }
        Text("학교에서 확인한 현황을 준비 중이에요.", fontSize = 12.sp)
    }
}
