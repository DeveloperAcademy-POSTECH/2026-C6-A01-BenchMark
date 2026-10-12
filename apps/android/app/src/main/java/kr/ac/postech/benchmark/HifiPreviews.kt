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
