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
@Config(sdk = [35], qualifiers = "w402dp-h874dp-mdpi", application = NavigationTestApplication::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class HifiVisualTest {
    @get:Rule val ui = createAndroidComposeRule<MainActivity>()
    private fun tap(tag: String) { ui.onNodeWithTag(tag).performScrollTo().performClick() }
    private fun shot(name: String, width: Int) {
        ui.waitForIdle()
        ui.runOnIdle {
            val view = ui.activity.window.decorView
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(android.graphics.Canvas(bitmap))
            val file = File("build/hifi-screenshots/$name-$width.png")
            requireNotNull(file.parentFile).mkdirs()
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        }
    }
    private fun captureFlow(width: Int) {
        ui.waitUntil(5_000) { ui.onAllNodesWithTag("skip-onboarding").fetchSemanticsNodes().size == 1 }
        shot("onboarding", width); tap("skip-onboarding"); tap("onboarding-next")
        ui.onNodeWithTag("tab-MY_DONATIONS").performClick(); shot("donations-empty", width)
        ui.onNodeWithText("기부 내역 예시 불러오기").performScrollTo().performClick()
        shot("donations-single", width); tap("grid-layout"); shot("donations-grid", width)
        tap("flip-1"); shot("donations-map", width)
        ui.onNodeWithTag("tab-SUPPORT").performClick(); shot("support-intro", width)
        tap("next"); shot("support-steps", width); tap("next"); shot("support-terms", width)
        ui.onNodeWithText("[필수] 개인정보 수집 동의").performScrollTo().performClick()
        tap("next"); tap("verify"); shot("support-amount", width)
        tap("fill-amount"); tap("next"); shot("support-category", width); tap("next")
        shot("support-donor", width); ui.onNodeWithTag("donor-name").performTextInput("예시 작성자"); tap("next")
        ui.onNodeWithTag("story-title").performTextInput("함께했던 오후")
        ui.onNodeWithTag("story-body").performScrollTo().performTextInput("캠퍼스에서 나눴던 이야기를 남깁니다.")
        tap("edit-photo"); tap("allow-photo"); tap("photo-1"); tap("photo-done")
        shot("support-story", width); tap("next"); shot("support-review", width)
        tap("submit-example"); shot("support-receipt", width)
    }
    @Test fun referenceScreens() = captureFlow(402)
    @Test @Config(qualifiers = "w320dp-h640dp-mdpi") fun smallScreens() = captureFlow(320)
    @Test @Config(qualifiers = "w600dp-h960dp-mdpi") fun largeScreens() = captureFlow(600)
}
