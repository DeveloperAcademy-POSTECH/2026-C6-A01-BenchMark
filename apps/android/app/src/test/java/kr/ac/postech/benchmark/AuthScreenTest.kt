package kr.ac.postech.benchmark

import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import java.io.File
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

class UnconfiguredGuestApplication : kr.ac.postech.benchmark.auth.BenchmarkApplication() {
    override fun createAuthService(): kr.ac.postech.benchmark.auth.AuthService = FakeAuthService(configured = false)
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w402dp-h874dp-mdpi", application = AuthTestApplication::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AuthScreenTest {
    @get:Rule val ui = createAndroidComposeRule<MainActivity>()
    private fun screenshot(name: String) {
        ui.runOnIdle {
            val view = ui.activity.window.decorView
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(android.graphics.Canvas(bitmap))
            val file = File("build/hifi-screenshots/$name.png")
            requireNotNull(file.parentFile).mkdirs()
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        }
    }
    @Test fun guestEntersHomeAndChoosesGoogleLoginOnlyWhenNeeded() {
        ui.onNodeWithTag("home-donate").assertExists()
        ui.onNodeWithTag("google-login").assertDoesNotExist()
        screenshot("guest-home-402")
        ui.onNodeWithContentDescription("프로필").performClick()
        ui.onNodeWithTag("google-login").assertIsEnabled()
        ui.onNodeWithText("로그인 예시로 시작").assertDoesNotExist()
        ui.onNodeWithText("Apple로 계속하기").assertDoesNotExist()
        ui.onNodeWithTag("close-login").performScrollTo().performClick()
        ui.onNodeWithTag("home-donate").assertExists()
    }
    @Test fun optionalLoginReturnsToRequestedAccountScreen() {
        val service = (ui.activity.application as AuthTestApplication).fake
        ui.onNodeWithTag("tab-MY_DONATIONS").performClick()
        ui.onNodeWithTag("google-login").assertExists()
        ui.runOnIdle { service.sessions.value = kr.ac.postech.benchmark.auth.AuthSession.SignedIn(
            kr.ac.postech.benchmark.auth.AuthAccount("requested-user", null)) }
        ui.waitUntil(5_000) { ui.onAllNodesWithTag("skip-onboarding").fetchSemanticsNodes().size == 1 }
        ui.onNodeWithTag("skip-onboarding").performScrollTo().performClick()
        ui.onNodeWithTag("onboarding-next").performScrollTo().performClick()
        ui.onNodeWithText("아직 기부 내역이 없습니다").assertExists()
    }
    @Test @Config(application = UnconfiguredGuestApplication::class)
    fun missingOAuthConfigurationDoesNotBlockPublicHome() {
        ui.onNodeWithTag("home-donate").assertExists()
        ui.onNodeWithContentDescription("프로필").performClick()
        ui.onNodeWithTag("google-login").assertIsNotEnabled()
        ui.onNodeWithTag("close-login").performScrollTo().performClick()
        ui.onNodeWithTag("home-donate").assertExists()
    }
    @Test fun guestBenchSelectionSurvivesLoginAndActivityRecreation() {
        val service = (ui.activity.application as AuthTestApplication).fake
        ui.onNodeWithText("기부할 벤치 찾기").performScrollTo().performClick()
        ui.onNodeWithText("벤치 2 · 기부 가능").performScrollTo().performClick()
        ui.onNodeWithTag("select-bench").performScrollTo().performClick()
        ui.onNodeWithTag("start-donation").performScrollTo().performClick()
        repeat(2) { ui.onNodeWithTag("next").performScrollTo().performClick() }
        ui.onNodeWithTag("google-login").assertExists()
        ui.activityRule.scenario.recreate()
        ui.onNodeWithTag("google-login").assertExists()
        ui.runOnIdle { service.sessions.value = kr.ac.postech.benchmark.auth.AuthSession.SignedIn(
            kr.ac.postech.benchmark.auth.AuthAccount("bench-user", null)) }
        ui.waitUntil(5_000) { ui.onAllNodesWithTag("skip-onboarding").fetchSemanticsNodes().size == 1 }
        ui.onNodeWithTag("skip-onboarding").performScrollTo().performClick()
        ui.onNodeWithTag("onboarding-next").performScrollTo().performClick()
        ui.onNodeWithText("[필수] 개인정보 수집 동의").performScrollTo().performClick()
        ui.onNodeWithTag("next").performScrollTo().performClick()
        ui.onNodeWithTag("verify").performScrollTo().performClick()
        ui.onNodeWithTag("fill-amount").performScrollTo().performClick()
        repeat(3) { ui.onNodeWithTag("next").performScrollTo().performClick() }
        ui.onNodeWithTag("story-title").performTextInput("벤치 선택 복원")
        ui.onNodeWithTag("story-body").performScrollTo().performTextInput("선택한 장소를 유지합니다.")
        ui.onNodeWithTag("next").performScrollTo().performClick()
        ui.onNodeWithText("벤치 2").assertExists()
    }
    @Test fun unavailableSessionStillAllowsPublicHome() {
        val service = (ui.activity.application as AuthTestApplication).fake
        ui.runOnIdle { service.sessions.value = kr.ac.postech.benchmark.auth.AuthSession.Unavailable }
        ui.onNodeWithTag("home-donate").assertExists()
        ui.onNodeWithContentDescription("프로필").performClick()
        ui.onNodeWithTag("auth-error").assertExists()
        ui.onNodeWithTag("close-login").performScrollTo().performClick()
        ui.onNodeWithTag("home-donate").assertExists()
    }
    @Test fun logoutClearsAccountDraftBeforeRelogin() {
        val service = (ui.activity.application as AuthTestApplication).fake
        ui.runOnIdle { service.sessions.value = kr.ac.postech.benchmark.auth.AuthSession.SignedIn(
            kr.ac.postech.benchmark.auth.AuthAccount("same-user", null)) }
        ui.waitUntil(5_000) { ui.onAllNodesWithTag("skip-onboarding").fetchSemanticsNodes().size == 1 }
        ui.onNodeWithTag("skip-onboarding").performScrollTo().performClick()
        ui.onNodeWithTag("onboarding-next").performScrollTo().performClick()
        ui.onNodeWithContentDescription("프로필").performClick()
        ui.onNodeWithTag("donor-name").performScrollTo().performTextInput("Private draft")
        ui.onNodeWithText("로그아웃").performScrollTo().performClick()
        ui.onNodeWithTag("home-donate").assertExists()
        ui.onNodeWithText("Private draft").assertDoesNotExist()
        ui.runOnIdle { service.sessions.value = kr.ac.postech.benchmark.auth.AuthSession.SignedIn(
            kr.ac.postech.benchmark.auth.AuthAccount("same-user", null)) }
        ui.waitUntil(5_000) { ui.onAllNodesWithTag("enter-profile").fetchSemanticsNodes().size == 1 }
        ui.onNodeWithTag("enter-profile").performScrollTo().performClick()
        ui.onNodeWithTag("onboarding-next").performScrollTo().performClick()
        ui.onNodeWithText("Private draft").assertDoesNotExist()
    }
}
