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
@Config(sdk = [35], qualifiers = "w402dp-h874dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class NavigationTest {
    @get:Rule val ui = createAndroidComposeRule<MainActivity>()

    private fun tap(tag: String) { ui.onNodeWithTag(tag).performScrollTo().performClick() }
    private fun button(text: String) { ui.onNodeWithText(text).performScrollTo().performClick() }
    private fun back() { ui.onNodeWithTag("back").performClick() }
    private fun home() { tap("login"); tap("skip-onboarding") }
    private fun screenshot(name: String) {
        val file = File("build/lofi-screenshots/$name.png")
        requireNotNull(file.parentFile).mkdirs()
        ui.runOnIdle {
            val view = ui.activity.window.decorView
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(android.graphics.Canvas(bitmap))
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        }
    }
    private fun startDonation() {
        button("기부할 벤치 찾기"); tap("select-bench"); tap("start-donation"); tap("next")
        ui.onNodeWithTag("next").assertIsNotEnabled()
        button("[필수] 개인정보 수집 동의"); tap("next"); tap("verify")
        ui.onNodeWithTag("next").assertIsNotEnabled()
        ui.onNodeWithTag("amount").performTextInput("999999")
        ui.onNodeWithTag("next").assertIsNotEnabled()
        tap("fill-amount"); tap("next"); tap("next")
    }

    @Test fun donationPhotoReceiptAndBackStack() {
        home(); screenshot("home"); startDonation()
        ui.onNodeWithTag("story-title").performTextInput("캠퍼스의 기억")
        ui.onNodeWithTag("story-body").performScrollTo().performTextInput("함께 쉬던 자리")
        tap("edit-photo"); tap("deny-photo"); button("사진 없이 돌아가기")
        ui.onNodeWithTag("story-title").assertTextContains("캠퍼스의 기억")
        tap("edit-photo"); tap("allow-photo"); tap("photo-1"); tap("photo-done")
        tap("next"); tap("submit-example"); screenshot("receipt")
        button("나의 기부 보기")
        ui.onNodeWithText("캠퍼스의 기억").assertExists()
        button("캠퍼스의 기억"); screenshot("donation")
        back(); back()
        ui.onNodeWithText("기부할 벤치 찾기").assertExists()
        ui.onNodeWithText("접수 완료! (예시)").assertDoesNotExist()
    }

    @Test fun editingCancelAndSaveHaveSeparateState() {
        home(); button("나의 기부 현황"); button("기부 내역 예시 불러오기"); button("작은 쉼")
        tap("open-edit")
        ui.onNodeWithTag("story-title").performTextReplacement("취소할 제목")
        button("취소")
        ui.onNodeWithText("작은 쉼").assertExists()
        ui.onNodeWithText("취소할 제목").assertDoesNotExist()
        tap("open-edit")
        ui.onNodeWithTag("story-title").performTextReplacement("저장할 제목")
        button("미리보기"); ui.onNodeWithText("저장할 제목").assertExists(); back()
        tap("save-edit"); ui.onNodeWithText("저장할 제목").assertExists()
        button("설치 프로세스 확인")
        repeat(3) { tap("advance-stage") }
        button("설치된 벤치 보기")
        ui.onNodeWithText("설치된 벤치 이미지 / 3D 영역").assertExists()
        screenshot("installed")
    }

    @Test fun onboardingProfileAndDraftSurviveRecreation() {
        tap("login"); tap("enter-profile")
        ui.onNodeWithTag("donor-name").performScrollTo().performTextInput("예시 사용자")
        tap("next"); tap("verify")
        startDonation()
        ui.onNodeWithTag("story-title").performTextInput("복원할 제목")
        ui.activityRule.scenario.recreate()
        ui.onNodeWithTag("story-title").assertTextContains("복원할 제목")
        back()
        ui.onNodeWithTag("donor-name").assertTextContains("예시 사용자")
    }

    @Test fun nfcArDenialRetryCaptureAndReturn() {
        home(); button("NFC 벤치 체험"); tap("nfc-example"); button("AR 카메라 열기")
        tap("start-ar"); ui.onNodeWithText("허용 안 함").performClick()
        ui.onNodeWithText("권한 거부 예시 · 체험을 다시 시작하거나 이전 화면으로 돌아갈 수 있습니다.").assertExists()
        tap("start-ar")
        repeat(3) { ui.onNodeWithText("허용 예시").performClick() }
        tap("capture"); button("저장 결과 예시 보기")
        screenshot("capture")
        button("다시 촬영"); ui.onNodeWithTag("capture").assertExists()
    }

    @Test fun repeatedTabsDoNotAccumulateAndResetClearsExamples() {
        home()
        repeat(3) {
            ui.onNodeWithTag("tab-MY_DONATIONS").performClick()
            ui.onNodeWithTag("tab-BENCHES").performClick()
            ui.onNodeWithTag("tab-NFC").performClick()
        }
        back(); ui.onNodeWithText("기부할 벤치 찾기").assertExists()
        button("나의 기부 현황"); button("기부 내역 예시 불러오기")
        ui.onNodeWithText("프로필").performClick(); button("예시 초기화 및 처음으로")
        home(); button("나의 기부 현황")
        ui.onNodeWithText("아직 기부 내역이 없습니다").assertExists()
    }

    @Test @Config(qualifiers = "w320dp-h640dp-mdpi")
    fun smallScreenScrollAndNavigation() {
        home(); startDonation()
        ui.onNodeWithTag("story-body").performScrollTo().performTextInput("작은 화면 확인")
        tap("next"); ui.onNodeWithText("작은 화면 확인").assertExists()
        screenshot("small-screen")
    }
}
