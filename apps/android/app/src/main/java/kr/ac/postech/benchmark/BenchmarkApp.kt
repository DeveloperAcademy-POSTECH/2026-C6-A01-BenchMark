package kr.ac.postech.benchmark

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import androidx.navigation.compose.*

private val tabs = listOf(Screen.HOME, Screen.MY_DONATIONS, Screen.BENCHES, Screen.NFC)

private fun NavHostController.open(screen: Screen) { navigate(screen.name) { launchSingleTop = true } }

private fun NavHostController.tab(screen: Screen) {
    navigate(screen.name) { popUpTo(Screen.HOME.name); launchSingleTop = true }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BenchmarkApp(model: LofiModel, signOut: () -> Unit) {
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val current = Screen.entries.firstOrNull { it.name == entry?.destination?.route } ?: Screen.INTENT
    val state = model.state
    fun open(screen: Screen) = nav.open(screen)
    fun home() { nav.navigate(Screen.HOME.name) { popUpTo(Screen.INTENT.name) { inclusive = true }; launchSingleTop = true } }
    fun back() { nav.popBackStack() }

    Scaffold(
        topBar = {
            Column {
                TopAppBar(title = { Text(current.title) }, navigationIcon = {
                    if (current != Screen.INTENT && current != Screen.HOME) {
                        TextButton({ back() }, Modifier.testTag("back")) { Text("뒤로") }
                    }
                }, actions = {
                    if (current in tabs) {
                        TextButton({ open(Screen.NOTIFICATIONS) }) { Text("알림") }
                        TextButton({ open(Screen.PROFILE) }) { Text("프로필") }
                    }
                })
                Text("Lo-fi 미리보기 · 본인인증·결제·접수는 예시", Modifier.padding(horizontal = 20.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelMedium)
            }
        },
        bottomBar = {
            if (current in tabs) NavigationBar {
                tabs.forEach { screen ->
                    val label = when (screen) {
                        Screen.HOME -> "홈"
                        Screen.BENCHES -> "벤치"
                        Screen.NFC -> "AR 체험"
                        else -> "나의 기부"
                    }
                    NavigationBarItem(current == screen, { nav.tab(screen) },
                        icon = { Text(when (screen) { Screen.HOME -> "⌂"; Screen.BENCHES -> "▤"; Screen.NFC -> "◎"; else -> "♡" }) },
                        label = { Text(label) }, modifier = Modifier.testTag("tab-${screen.name}"))
                }
            }
        }
    ) { padding ->
        NavHost(nav, Screen.INTENT.name, Modifier.padding(padding)) {
            Screen.entries.forEach { screen ->
                composable(screen.name) {
                    when (screen) {
                        Screen.INTENT -> Page {
                            Heading("기부자 정보를 입력하시겠습니까?")
                            Text("이 정보는 기부 접수시에 자동입력 됩니다.")
                            Action("네", "enter-profile") { open(Screen.ONBOARDING_PROFILE) }
                            Action("아니오 · 건너뛰기", "skip-onboarding") { home() }
                        }
                        Screen.ONBOARDING_PROFILE, Screen.DONOR, Screen.PROFILE -> Page {
                            DonorFields(state.donor) { donor -> model.update { it.copy(donor = donor) } }
                            Action(if (screen == Screen.PROFILE) "완료" else "다음", "next") {
                                when (screen) {
                                    Screen.ONBOARDING_PROFILE -> open(Screen.ONBOARDING_VERIFY)
                                    Screen.DONOR -> open(Screen.STORY)
                                    else -> back()
                                }
                            }
                            if (screen == Screen.ONBOARDING_PROFILE) TextButton({ home() }) { Text("건너뛰기") }
                            if (screen == Screen.PROFILE) TextButton({ model.reset(); signOut() }) { Text("로그아웃") }
                            if (screen == Screen.PROFILE) TextButton({
                                model.reset()
                                nav.navigate(Screen.INTENT.name) { popUpTo(nav.graph.id) { inclusive = true } }
                            }) { Text("예시 초기화 및 처음으로") }
                        }
                        Screen.ONBOARDING_VERIFY, Screen.VERIFY -> VerificationScreen {
                            if (screen == Screen.ONBOARDING_VERIFY) home() else open(Screen.AMOUNT)
                        }
                        Screen.HOME -> Page {
                            Block("캠퍼스의 기억이 누군가의 쉼이 됩니다.")
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                                Text("설치된 벤치\n00개"); Text("누적 참여자\n00명")
                            }
                            Action("기부할 벤치 찾기") { nav.tab(Screen.BENCHES) }
                            Action("나의 기부 현황") { nav.tab(Screen.MY_DONATIONS) }
                            Action("NFC 벤치 체험") { nav.tab(Screen.NFC) }
                        }
                        Screen.BENCHES -> BenchScreen(state.bench, { bench -> model.update { it.copy(bench = bench) } }) {
                            open(Screen.BENCH)
                        }
                        Screen.BENCH -> Page {
                            Block("선택한 벤치 ${state.bench}\n지도 / 벤치 이미지 영역", 240)
                            Text("캠퍼스 위치 ${state.bench} · 기부 가능 (예시)")
                            Action("기부 시작", "start-donation") { model.startDonation(); open(Screen.GUIDE) }
                        }
                        Screen.GUIDE -> Page { DonationGuide(); Action("다음", "next") { open(Screen.TERMS) } }
                        Screen.TERMS -> TermsScreen(state, model::update) { open(Screen.VERIFY) }
                        Screen.AMOUNT -> AmountScreen(state.amount, { value -> model.update { it.copy(amount = value) } }) {
                            open(Screen.DONOR)
                        }
                        Screen.STORY -> Page {
                            Text("3 / 4 · 이야기")
                            StoryFields(state.draft, { story -> model.update { it.copy(draft = story) } }) { open(Screen.PHOTO) }
                            Action("다음", "next") { open(Screen.REVIEW) }
                        }
                        Screen.PHOTO -> PhotoScreen(
                            editing = nav.previousBackStackEntry?.destination?.route == Screen.EDIT.name,
                            state = state, update = model::update, done = { back() }
                        )
                        Screen.REVIEW -> Page {
                            Text("4 / 4 · 접수 내용 확인")
                            Heading("벤치 ${state.bench}")
                            Text("기부금 ${state.amount}원 · ${state.donor.name.ifBlank { "이름 미입력" }}")
                            StoryContent(state.draft)
                            Text("결제 및 접수 화면 예시입니다. 결제 수단을 연결하거나 실제 접수하지 않습니다.")
                            Action("접수 완료 화면 보기", "submit-example") {
                                model.submitExample()
                                nav.navigate(Screen.RECEIPT.name) { popUpTo(Screen.BENCH.name); launchSingleTop = true }
                            }
                        }
                        Screen.RECEIPT -> Page {
                            Block("✓", 180); Heading("접수 완료! (예시)")
                            Text("화면 확인용 기부 내역을 추가했습니다.")
                            Action("나의 기부 보기") { nav.tab(Screen.MY_DONATIONS) }
                            Action("홈으로") { nav.tab(Screen.HOME) }
                        }
                        Screen.MY_DONATIONS -> MyDonationsScreen(state, { id ->
                            model.update { it.copy(selectedDonation = id) }; open(Screen.DONATION)
                        }, { nav.tab(Screen.BENCHES) }, { model.loadExample() })
                        Screen.DONATION, Screen.PROGRESS, Screen.INSTALLED -> DonationScreen(
                            screen, model.selectedDonation,
                            edit = { model.beginEdit(); open(Screen.EDIT) },
                            preview = { open(Screen.PREVIEW) },
                            progress = { open(Screen.PROGRESS) },
                            installed = { open(Screen.INSTALLED) },
                            setStage = { stage -> model.update { currentState -> currentState.copy(
                                donations = currentState.donations.map { if (it.id == currentState.selectedDonation) it.copy(stage = stage) else it }
                            ) } }
                        )
                        Screen.EDIT -> Page {
                            StoryFields(state.editDraft, { story -> model.update { it.copy(editDraft = story) } }) { open(Screen.PHOTO) }
                            Action("미리보기") { open(Screen.PREVIEW) }
                            Action("저장", "save-edit") { model.saveEdit(); back() }
                            TextButton({ back() }) { Text("취소") }
                        }
                        Screen.PREVIEW -> Page {
                            val editing = nav.previousBackStackEntry?.destination?.route == Screen.EDIT.name
                            StoryContent(if (editing) state.editDraft else model.selectedDonation?.story ?: Story())
                            Action("돌아가기") { back() }
                        }
                        Screen.NFC -> Page {
                            Heading("태그하세요")
                            Block("NFC\n기부자의 이야기를 확인해보세요\n휴대폰을 가까이 대보세요", 260)
                            Action("태그 결과 예시 보기", "nfc-example") { open(Screen.PUBLIC_STORY) }
                        }
                        Screen.PUBLIC_STORY -> Page {
                            StoryContent(Story("작은 쉼", "오늘의 작은 기부가 어느 날의 작은 쉼이 되길 바랍니다.", 1))
                            ReactionButtons(state.reaction) { value -> model.update { it.copy(reaction = value) } }
                            Action("AR 카메라 열기") { open(Screen.AR) }
                        }
                        Screen.AR -> ArScreen()
                        Screen.NOTIFICATIONS -> Page { Heading("새 알림이 없습니다"); Text("실제 알림은 아직 연결하지 않았습니다.") }
                    }
                }
            }
        }
    }
}
