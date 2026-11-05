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

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = NavigationTestApplication::class, qualifiers = "w402dp-h874dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class HifiHomeTest {
    @get:Rule val ui = createAndroidComposeRule<MainActivity>()

    private fun home() {
        ui.waitUntil(5_000) { ui.onAllNodesWithTag("skip-onboarding").fetchSemanticsNodes().size == 1 }
        ui.onNodeWithTag("skip-onboarding").performScrollTo().performClick()
        ui.onNodeWithTag("onboarding-next").performScrollTo().performClick()
    }
    private fun screenshot(name: String) {
        val file = File("build/hifi-screenshots/$name.png")
        requireNotNull(file.parentFile).mkdirs()
        ui.runOnIdle {
            val view = ui.activity.window.decorView
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(android.graphics.Canvas(bitmap))
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        }
    }
    @Test fun homeShowsUnavailableMetricsAndOpensBenchFlow() {
        home()
        ui.onNodeWithText("235").assertDoesNotExist()
        ui.onNodeWithText("— / —").assertExists()
        screenshot("home-402")
        ui.onNodeWithTag("home-donate").performScrollTo().performClick()
        ui.onNodeWithTag("select-bench").assertExists()
    }
    @Test fun receiptExplainsSchoolOwnership() {
        home()
        ui.onNodeWithText("기부금영수증").performScrollTo().performClick()
        ui.onNodeWithText("영수증은 학교의 공식 기부 절차에서 발급됩니다. 앱의 로컬 예시 내역은 납입 증빙이 아닙니다.").assertExists()
        ui.onNodeWithText("확인").performClick()
        ui.onNodeWithContentDescription("프로필").performClick()
        ui.onNodeWithTag("donor-name").assertExists()
    }
    @Test @Config(qualifiers = "w320dp-h640dp-mdpi")
    fun smallHomeKeepsDonationReachable() {
        home(); screenshot("home-320")
        ui.onNodeWithTag("home-donate").performScrollTo().performClick()
        ui.onNodeWithTag("select-bench").assertExists()
    }
    @Test @Config(qualifiers = "w600dp-h960dp-mdpi")
    fun largeHomeUsesAvailableWidth() {
        home(); screenshot("home-600")
        ui.onNodeWithTag("home-donations").performScrollTo().performClick()
        ui.onNodeWithText("아직 기부 내역이 없습니다").assertExists()
    }
}
