package kr.ac.postech.benchmark

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun HifiOnboarding(enter: () -> Unit, skip: () -> Unit) {
    var wantsProfile by rememberSaveable { mutableStateOf(true) }
    Column(Modifier.fillMaxSize().background(Color(0xFFF7FAEF)).verticalScroll(rememberScrollState())
        .padding(20.dp), verticalArrangement = Arrangement.spacedBy(31.dp)) {
        Box(Modifier.fillMaxWidth().height(15.dp).background(OiColors.Shortcut, RoundedCornerShape(30.dp))) {
            Box(Modifier.fillMaxWidth(.307f).fillMaxHeight().background(Brush.horizontalGradient(
                listOf(OiColors.Green, OiColors.Shortcut)), RoundedCornerShape(30.dp)))
        }
        Row(Modifier.fillMaxWidth().background(OiColors.Shortcut, RoundedCornerShape(15.dp)).padding(16.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Image(painterResource(R.drawable.onboarding_cucumber), null, Modifier.size(25.dp, 31.dp))
            Text("기부자 정보를 입력하시겠습니까?", color = OiColors.Olive, fontSize = 20.sp)
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            OnboardingChoice(true, wantsProfile, Modifier.weight(1f)) { wantsProfile = true }
            OnboardingChoice(false, !wantsProfile, Modifier.weight(1f)) { wantsProfile = false }
        }
        Spacer(Modifier.height(130.dp))
        Text("* 입력한 이야기 작성자 정보는 로컬 신청 예시에 사용됩니다.\n   프로필에서 입력하거나 수정할 수 있습니다.", color = OiColors.Green, fontSize = 14.sp)
        OiButton("다음", "onboarding-next") { if (wantsProfile) enter() else skip() }
    }
}

@Composable
private fun OnboardingChoice(yes: Boolean, selected: Boolean, modifier: Modifier, choose: () -> Unit) {
    Box(modifier.aspectRatio(173f / 205f).border(if (selected && !yes) 3.dp else 0.dp, OiColors.Accent, RoundedCornerShape(40.dp))
        .selectable(selected, role = Role.RadioButton, onClick = choose)
        .semantics { contentDescription = if (yes) "기부자 정보 입력" else "정보 입력 건너뛰기" }
        .testTag(if (yes) "enter-profile" else "skip-onboarding")) {
        Image(painterResource(if (yes) R.drawable.onboarding_yes else R.drawable.onboarding_no), null, Modifier.fillMaxSize())
    }
}
