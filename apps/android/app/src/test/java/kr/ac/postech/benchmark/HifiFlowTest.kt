package kr.ac.postech.benchmark

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w402dp-h874dp-mdpi", application = NavigationTestApplication::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class HifiFlowTest {
    @get:Rule val ui = createAndroidComposeRule<MainActivity>()
    private fun tap(tag: String) { ui.onNodeWithTag(tag).performScrollTo().performClick() }
    private fun home() {
        ui.waitUntil(5_000) { ui.onAllNodesWithTag("skip-onboarding").fetchSemanticsNodes().size == 1 }
        tap("skip-onboarding"); tap("onboarding-next")
    }
    @Test fun onboardingSelectionSurvivesRecreation() {
        ui.waitUntil(5_000) { ui.onAllNodesWithTag("skip-onboarding").fetchSemanticsNodes().size == 1 }
        tap("skip-onboarding"); ui.activityRule.scenario.recreate()
        ui.onNodeWithTag("skip-onboarding").assertIsSelected()
        tap("onboarding-next"); ui.onNodeWithTag("home-donate").assertExists()
    }
    @Test fun supportTabWalksAllStepsAndKeepsDraft() {
        home(); ui.onNodeWithTag("tab-SUPPORT").performClick(); tap("next"); tap("next")
        ui.onNodeWithTag("next").assertIsNotEnabled()
        ui.onNodeWithText("[필수] 개인정보 수집 동의").performScrollTo().performClick()
        tap("next"); tap("verify")
        ui.onNodeWithTag("amount").performTextInput("49999")
        ui.onNodeWithTag("next").assertIsNotEnabled(); tap("fill-amount"); tap("next")
        ui.onNodeWithText("연구원").performScrollTo().performClick(); tap("next")
        ui.onNodeWithTag("donor-identity").assertIsNotEnabled()
        ui.onNodeWithTag("donor-name").performTextInput("이야기 작성자"); tap("next")
        ui.onNodeWithTag("next").assertIsNotEnabled()
        ui.onNodeWithTag("story-title").performTextInput("기억")
        ui.onNodeWithTag("story-body").performScrollTo().performTextInput("함께했던 오후")
        ui.activityRule.scenario.recreate()
        ui.onNodeWithTag("story-title").assertTextContains("기억")
        tap("next"); tap("submit-example")
        ui.onNodeWithText("참여 신청\n예시 확인").assertExists()
        ui.onNodeWithText("기부 완료").assertDoesNotExist()
    }
    @Test @Config(sdk = [26], qualifiers = "w320dp-h640dp-mdpi")
    fun minimumApiKeepsOnboardingAndSupportUsable() {
        home(); ui.onNodeWithTag("tab-SUPPORT").performClick(); tap("next"); tap("next")
        ui.onNodeWithText("[필수] 개인정보 수집 동의").performScrollTo().performClick()
        tap("next"); tap("verify"); tap("fill-amount"); tap("next")
        ui.onNodeWithText("동문").assertExists()
    }
    @Test fun cardsSwitchSortFlipAndRestoreLayout() {
        home(); ui.onNodeWithTag("tab-MY_DONATIONS").performClick()
        ui.onNodeWithText("기부 내역 예시 불러오기").performScrollTo().performClick()
        tap("like-1")
        ui.onNodeWithText("좋아요순").performScrollTo().performClick()
        tap("flip-1"); ui.onNodeWithText("벤치 1 · 지도 예시").assertExists(); tap("flip-1")
        tap("grid-layout"); ui.activityRule.scenario.recreate()
        ui.onNodeWithTag("grid-layout").assertIsSelected()
        ui.onNodeWithText("오래된순").performScrollTo().performClick()
        ui.onNodeWithTag("donation-card-5").assertExists()
    }
}
