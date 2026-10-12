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
@Config(sdk = [35], qualifiers = "w402dp-h874dp-mdpi", application = AuthTestApplication::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AuthScreenTest {
    @get:Rule val ui = createAndroidComposeRule<MainActivity>()
    @Test fun signedOutUserCannotEnterAppAndSeesGoogleOnly() {
        ui.onNodeWithTag("google-login").assertIsEnabled()
        ui.onNodeWithText("기부할 벤치 찾기").assertDoesNotExist()
        ui.onNodeWithText("로그인 예시로 시작").assertDoesNotExist()
        ui.onNodeWithText("Apple로 계속하기").assertDoesNotExist()
        ui.runOnIdle {
            val view = ui.activity.window.decorView
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(android.graphics.Canvas(bitmap))
            val file = File("build/lofi-screenshots/google-login.png")
            requireNotNull(file.parentFile).mkdirs()
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        }
    }
    @Test fun logoutClearsAccountDraftBeforeRelogin() {
        val service = (ui.activity.application as AuthTestApplication).fake
        ui.runOnIdle { service.sessions.value = kr.ac.postech.benchmark.auth.AuthSession.SignedIn(
            kr.ac.postech.benchmark.auth.AuthAccount("same-user", null)) }
        ui.waitUntil(5_000) { ui.onAllNodesWithTag("skip-onboarding").fetchSemanticsNodes().size == 1 }
        ui.onNodeWithTag("skip-onboarding").performScrollTo().performClick()
        ui.onNodeWithText("프로필").performClick()
        ui.onNodeWithTag("donor-name").performScrollTo().performTextInput("Private draft")
        ui.onNodeWithText("로그아웃").performScrollTo().performClick()
        ui.onNodeWithTag("google-login").assertExists()
        ui.onNodeWithText("기부할 벤치 찾기").assertDoesNotExist()
        ui.runOnIdle { service.sessions.value = kr.ac.postech.benchmark.auth.AuthSession.SignedIn(
            kr.ac.postech.benchmark.auth.AuthAccount("same-user", null)) }
        ui.waitUntil(5_000) { ui.onAllNodesWithTag("enter-profile").fetchSemanticsNodes().size == 1 }
        ui.onNodeWithTag("enter-profile").performScrollTo().performClick()
        ui.onNodeWithText("Private draft").assertDoesNotExist()
    }
}
