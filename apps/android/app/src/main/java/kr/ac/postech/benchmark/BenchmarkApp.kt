package kr.ac.postech.benchmark

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.Place
import androidx.compose.ui.res.painterResource
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import androidx.navigation.compose.*

private val tabs = listOf(Screen.HOME, Screen.MY_DONATIONS, Screen.SUPPORT, Screen.BENCHES)
private val hifiScreens = setOf(Screen.INTENT, Screen.ONBOARDING_PROFILE, Screen.SUPPORT, Screen.GUIDE,
    Screen.STEPS, Screen.TERMS, Screen.AMOUNT, Screen.CATEGORY, Screen.DONOR, Screen.STORY,
    Screen.MY_DONATIONS, Screen.DONATION, Screen.EDIT, Screen.PREVIEW, Screen.REVIEW, Screen.RECEIPT)

private fun NavHostController.open(screen: Screen) { navigate(screen.name) { launchSingleTop = true } }

private fun NavHostController.tab(screen: Screen) {
    navigate(screen.name) { popUpTo(Screen.HOME.name); launchSingleTop = true }
}

private val accountScreens = setOf(Screen.ONBOARDING_PROFILE, Screen.ONBOARDING_VERIFY, Screen.MY_DONATIONS, Screen.PROFILE, Screen.NOTIFICATIONS, Screen.TERMS,
    Screen.VERIFY, Screen.AMOUNT, Screen.CATEGORY, Screen.DONOR, Screen.STORY, Screen.PHOTO, Screen.REVIEW,
    Screen.RECEIPT, Screen.DONATION, Screen.EDIT, Screen.PREVIEW, Screen.PROGRESS, Screen.INSTALLED)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BenchmarkApp(model: LofiModel, signedIn: Boolean, login: (Screen) -> Unit,
                 pendingRoute: Screen?, pendingBench: Int, pendingConsumed: () -> Unit, signOut: () -> Unit) {
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val initialScreen = remember(signedIn) { if (signedIn && !model.state.onboardingComplete) Screen.INTENT else Screen.HOME }
    val current = Screen.entries.firstOrNull { it.name == entry?.destination?.route } ?: initialScreen
    val state = model.state
    fun open(screen: Screen) = nav.open(screen)
    fun home() { model.update { it.copy(onboardingComplete = true) }; nav.navigate(Screen.HOME.name) { popUpTo(Screen.INTENT.name) { inclusive = true }; launchSingleTop = true } }
    fun back() { nav.popBackStack() }
    LaunchedEffect(signedIn, state.onboardingComplete, pendingRoute) {
        if (signedIn && state.onboardingComplete && pendingRoute != null) {
            if (nav.currentDestination?.route == Screen.INTENT.name) nav.navigate(Screen.HOME.name) { popUpTo(Screen.INTENT.name) { inclusive = true } }
            if (pendingRoute == Screen.TERMS) {
                model.startDonation()
                model.update { it.copy(bench = pendingBench) }
            }
            nav.open(pendingRoute)
            pendingConsumed()
        }
    }

    Scaffold(
        containerColor = if (current == Screen.INTENT) androidx.compose.ui.graphics.Color(0xFFF7FAEF) else androidx.compose.ui.graphics.Color.White,
        topBar = {
            if (current in hifiScreens && current != Screen.MY_DONATIONS) OiHeader(if (current == Screen.INTENT) null else ({ back() }))
            else if (current != Screen.HOME && current != Screen.MY_DONATIONS) Column {
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
            if (current in tabs || current == Screen.NFC) NavigationBar(containerColor = OiColors.Soft) {
                tabs.forEach { screen ->
                    val label = when (screen) {
                        Screen.HOME -> "홈"
                        Screen.BENCHES -> "벤치"
                        Screen.SUPPORT -> "후원"
                        else -> "나의 기부"
                    }
                    NavigationBarItem(current == screen, { if (!signedIn && screen in accountScreens) login(screen) else nav.tab(screen) },
                        icon = { Icon(when (screen) { Screen.HOME -> Icons.Default.Home; Screen.BENCHES -> Icons.Default.Place;
                            Screen.SUPPORT -> Icons.Default.ThumbUp; else -> Icons.Default.Favorite }, null) },
                        colors = NavigationBarItemDefaults.colors(indicatorColor = OiColors.Shortcut, selectedIconColor = OiColors.Green, selectedTextColor = OiColors.Green),
                        label = { Text(label) }, modifier = Modifier.testTag("tab-${screen.name}"))
                }
                NavigationBarItem(current == Screen.NFC, { nav.tab(Screen.NFC) }, icon = { Icon(painterResource(R.drawable.ic_camera), null) },
                    label = { Text("AR 카메라") }, modifier = Modifier.testTag("tab-NFC"))
            }
        }
    ) { padding ->
        NavHost(nav, initialScreen.name, Modifier.padding(padding)) {
            Screen.entries.forEach { screen ->
                composable(screen.name) {
                    if (!signedIn && screen in accountScreens) Page {
                        OiNotice("계정의 신청 내역과 개인정보는 로그인 후 확인할 수 있습니다.")
                        OiButton("로그인") { login(screen) }
                        OiButton("홈으로") { nav.tab(Screen.HOME) }
                    } else when (screen) {
                        Screen.INTENT -> HifiOnboarding({ open(Screen.ONBOARDING_PROFILE) }, { home() })
                        Screen.ONBOARDING_PROFILE -> HifiDonor(state.donor,
                            { donor -> model.update { it.copy(donor = donor) } },
                            { open(Screen.ONBOARDING_VERIFY) }, { home() })
                        Screen.DONOR -> HifiDonor(state.donor,
                            { donor -> model.update { it.copy(donor = donor) } }, { open(Screen.STORY) })
                        Screen.PROFILE -> Page {
                            DonorFields(state.donor) { donor -> model.update { it.copy(donor = donor) } }
                            Action("완료", "next") { back() }
                            TextButton({ model.reset(); signOut() }) { Text("로그아웃") }
                            TextButton({
                                model.reset()
                                nav.navigate(Screen.INTENT.name) { popUpTo(nav.graph.id) { inclusive = true } }
                            }) { Text("예시 초기화 및 처음으로") }
                        }
                        Screen.ONBOARDING_VERIFY, Screen.VERIFY -> VerificationScreen {
                            if (screen == Screen.ONBOARDING_VERIFY) home() else open(Screen.AMOUNT)
                        }
                        Screen.HOME -> HifiHomeScreen(state,
                            benches = { nav.tab(Screen.BENCHES) },
                            donations = { if (signedIn) nav.tab(Screen.MY_DONATIONS) else login(Screen.MY_DONATIONS) },
                            nfc = { nav.tab(Screen.NFC) },
                            profile = { if (signedIn) open(Screen.PROFILE) else login(Screen.PROFILE) },
                            notifications = { if (signedIn) open(Screen.NOTIFICATIONS) else login(Screen.NOTIFICATIONS) })
                        Screen.BENCHES -> BenchScreen(state.bench, { bench -> model.update { it.copy(bench = bench) } }) {
                            open(Screen.BENCH)
                        }
                        Screen.BENCH -> Page {
                            Block("선택한 벤치 ${state.bench}\n지도 / 벤치 이미지 영역", 240)
                            Text("캠퍼스 위치 ${state.bench} · 기부 가능 (예시)")
                            Action("기부 시작", "start-donation") { model.startDonation(); open(Screen.GUIDE) }
                        }
                        Screen.SUPPORT -> HifiSupportIntro { model.startDonation(); open(Screen.STEPS) }
                        Screen.GUIDE -> HifiSupportIntro { open(Screen.STEPS) }
                        Screen.STEPS -> HifiStepOverview { if (signedIn) open(Screen.TERMS) else login(Screen.TERMS) }
                        Screen.TERMS -> HifiTerms(state, model::update) { open(Screen.VERIFY) }
                        Screen.AMOUNT -> HifiAmount(state, model::update) { open(Screen.CATEGORY) }
                        Screen.CATEGORY -> HifiCategory(state.donor,
                            { donor -> model.update { it.copy(donor = donor) } }, { open(Screen.DONOR) })
                        Screen.STORY -> HifiStory(state.draft,
                            { story -> model.update { it.copy(draft = story) } },
                            { open(Screen.PHOTO) }, { open(Screen.REVIEW) })
                        Screen.PHOTO -> PhotoScreen(
                            editing = nav.previousBackStackEntry?.destination?.route == Screen.EDIT.name,
                            state = state, update = model::update, done = { back() }
                        )
                        Screen.REVIEW -> Page {
                            Text("참여 신청 예시 확인")
                            Heading("벤치 ${state.bench}")
                            Text("기부금 ${state.amount}원 · ${state.donor.name.ifBlank { "이름 미입력" }}")
                            DonationStoryCard(Donation(0, state.bench, state.amount, state.draft), false)
                            Text(state.draft.body)
                            OiNotice("로컬 신청 예시입니다. 실제 참여 신청·납입은 처리하지 않습니다. 학교 확인 전에는 기부 확인 대기입니다.")
                            OiButton("신청 내용 예시 확인", "submit-example") {
                                model.submitExample()
                                nav.navigate(Screen.RECEIPT.name) { popUpTo(Screen.HOME.name); launchSingleTop = true }
                            }
                        }
                        Screen.RECEIPT -> HifiReceipt({ nav.tab(Screen.MY_DONATIONS) }, { nav.tab(Screen.HOME) })
                        Screen.MY_DONATIONS -> HifiMyDonations(state, model::update, { id ->
                            model.update { it.copy(selectedDonation = id) }; open(Screen.DONATION)
                        }, { nav.tab(Screen.SUPPORT) }, { model.loadExample() }, model::toggleLike)
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
                        Screen.EDIT -> HifiStory(state.editDraft,
                            { story -> model.update { it.copy(editDraft = story) } }, { open(Screen.PHOTO) },
                            { model.saveEdit(); back() }, editing = true, cancel = { back() }, preview = { open(Screen.PREVIEW) })
                        Screen.PREVIEW -> Page {
                            val editing = nav.previousBackStackEntry?.destination?.route == Screen.EDIT.name
                            val story = if (editing) state.editDraft else model.selectedDonation?.story ?: Story()
                            DonationStoryCard(Donation(0, state.bench, state.amount, story), false)
                            Text(story.body)
                            OiButton("돌아가기") { back() }
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
