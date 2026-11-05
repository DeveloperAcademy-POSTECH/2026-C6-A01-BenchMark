package kr.ac.postech.benchmark

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

object OiColors {
    val Green = Color(0xFF708C40)
    val Dark = Color(0xFF435426)
    val Olive = Color(0xFF6A7837)
    val Soft = Color(0xFFF1F4EC)
    val Light = Color(0xFFF3F7E6)
    val Accent = Color(0xFFB0C85B)
    val Shortcut = Color(0xFFE7EECC)
}

@Composable
fun OiTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = lightColorScheme(
        primary = OiColors.Green, onPrimary = OiColors.Soft,
        secondary = OiColors.Olive, background = Color.White, surface = Color.White,
        surfaceVariant = OiColors.Soft, onSurface = OiColors.Dark,
        onSurfaceVariant = OiColors.Olive
    ), content = content)
}
