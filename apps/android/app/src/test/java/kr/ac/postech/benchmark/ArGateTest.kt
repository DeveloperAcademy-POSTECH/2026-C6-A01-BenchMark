package kr.ac.postech.benchmark

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import kr.ac.postech.benchmark.ar.ArGate
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w320dp-h640dp-mdpi")
class ArGateTest {
    @get:Rule val ui = createComposeRule()
    @Test fun denialKeepsRetrySettingsAndExitAccessible() {
        var retries = 0; var settings = 0; var backs = 0
        ui.setContent { MaterialTheme {
            ArGate("카메라 권한이 거부되었습니다.", { retries++ }, { settings++ }, { backs++ })
        } }
        ui.onNodeWithText("카메라 권한이 거부되었습니다.").assertExists()
        ui.onNodeWithText("카메라 허용 및 다시 시도").performScrollTo().performClick()
        ui.onNodeWithText("앱 권한 설정").performScrollTo().performClick()
        ui.onNodeWithText("돌아가기").performScrollTo().performClick()
        ui.runOnIdle { assertEquals(1, retries); assertEquals(1, settings); assertEquals(1, backs) }
    }
}
