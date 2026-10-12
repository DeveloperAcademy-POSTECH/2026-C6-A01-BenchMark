package kr.ac.postech.benchmark

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.tooling.preview.Preview

@Preview(name = "Reference 402", widthDp = 402, heightDp = 874, showBackground = true)
@Preview(name = "Small 320", widthDp = 320, heightDp = 640, showBackground = true)
@Preview(name = "Large 600", widthDp = 600, heightDp = 960, showBackground = true)
@Composable
private fun BenchPreview() {
    MaterialTheme { Surface { BenchScreen(1, {}, {}) } }
}

@Preview(name = "Story", widthDp = 402, heightDp = 874, showBackground = true)
@Preview(name = "Large text", widthDp = 320, heightDp = 640, fontScale = 1.5f, showBackground = true)
@Composable
private fun StoryPreview() {
    MaterialTheme {
        Surface {
            Page {
                StoryFields(Story("작은 쉼", "캠퍼스의 기억을 남깁니다.", 1), {}, {})
                Action("다음") {}
            }
        }
    }
}
