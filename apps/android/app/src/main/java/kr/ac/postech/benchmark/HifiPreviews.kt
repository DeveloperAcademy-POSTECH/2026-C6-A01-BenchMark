package kr.ac.postech.benchmark

import androidx.compose.runtime.Composable
import androidx.compose.ui.tooling.preview.Preview

@Preview(name = "Small Android home", widthDp = 320, heightDp = 640, showBackground = true)
@Preview(name = "Reference Android home", widthDp = 402, heightDp = 874, showBackground = true)
@Preview(name = "Large Android home", widthDp = 600, heightDp = 960, showBackground = true)
@Composable
private fun HifiHomePreview() {
    OiTheme {
        HifiHomeScreen(LofiState(), benches = {}, donations = {}, nfc = {}, profile = {}, notifications = {})
    }
}

@Preview(name = "Onboarding 402", widthDp = 402, heightDp = 874, showBackground = true)
@Preview(name = "Onboarding 320", widthDp = 320, heightDp = 640, showBackground = true)
@Preview(name = "Onboarding 600", widthDp = 600, heightDp = 960, showBackground = true)
@Composable
private fun HifiOnboardingPreview() { OiTheme { HifiOnboarding({}, {}) } }

@Preview(name = "Support 402", widthDp = 402, heightDp = 874, showBackground = true)
@Preview(name = "Support 320 large text", widthDp = 320, heightDp = 640, fontScale = 1.5f, showBackground = true)
@Preview(name = "Support 600", widthDp = 600, heightDp = 960, showBackground = true)
@Composable
private fun HifiSupportPreview() { OiTheme { HifiSupportIntro({}) } }

@Preview(name = "Donation card 402", widthDp = 402, heightDp = 874, showBackground = true)
@Preview(name = "Donation card 320", widthDp = 320, heightDp = 640, showBackground = true)
@Preview(name = "Donation card 600", widthDp = 600, heightDp = 960, showBackground = true)
@Composable
private fun HifiCardPreview() {
    OiTheme { DonationStoryCard(Donation(0, 1, "50000", Story("작은 쉼", "캠퍼스의 기억", 1)), false) }
}
