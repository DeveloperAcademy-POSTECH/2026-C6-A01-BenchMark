package kr.ac.postech.benchmark

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun OiHeader(back: (() -> Unit)? = null) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp).height(48.dp)) {
        if (back != null) IconButton(back, Modifier.align(Alignment.CenterStart).testTag("back")) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, "뒤로")
        }
        Row(Modifier.align(Alignment.Center), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Image(painterResource(R.drawable.oi_logo), null, Modifier.size(38.dp, 34.dp))
            Image(painterResource(R.drawable.oi_wordmark), "오이기부", Modifier.size(101.dp, 24.dp))
        }
    }
}

@Composable
fun OiButton(text: String, tag: String = text, enabled: Boolean = true, onClick: () -> Unit) {
    Button(onClick, Modifier.fillMaxWidth().heightIn(min = 57.dp).testTag(tag),
        enabled = enabled, shape = RoundedCornerShape(20.dp)) {
        Text(text, fontSize = 17.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun OiFormPage(step: Int, title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp).padding(bottom = 20.dp).drawBehind {
            drawLine(Color(0xFFD3DBC4), Offset(13.dp.toPx(), 0f), Offset(13.dp.toPx(), size.height), 6.dp.toPx())
        }, verticalArrangement = Arrangement.spacedBy(20.dp)) {
        if (step > 0) Row(Modifier.fillMaxWidth().background(OiColors.Soft, RoundedCornerShape(15.dp)),
            verticalAlignment = Alignment.CenterVertically) {
            Text("STEP %02d".format(step), fontSize = 18.sp, fontWeight = FontWeight.SemiBold,
                color = OiColors.Soft, modifier = Modifier.background(OiColors.Green, RoundedCornerShape(15.dp)).padding(8.dp))
            Text(title, Modifier.weight(1f).padding(horizontal = 12.dp, vertical = 8.dp), fontSize = 16.sp, color = OiColors.Dark)
        }
        Column(Modifier.padding(start = 34.dp), verticalArrangement = Arrangement.spacedBy(20.dp), content = content)
    }
}

@Composable
fun OiInput(label: String, value: String, tag: String, placeholder: String = "",
            multiline: Boolean = false, enabled: Boolean = true,
            keyboard: KeyboardType = KeyboardType.Text, error: String? = null, change: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
        Text(label, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.Black)
        OutlinedTextField(value, change, Modifier.fillMaxWidth().heightIn(min = 57.dp).testTag(tag),
            placeholder = { Text(placeholder, color = OiColors.Green.copy(alpha = .6f)) },
            singleLine = !multiline, minLines = if (multiline) 3 else 1, enabled = enabled,
            shape = RoundedCornerShape(10.dp), keyboardOptions = KeyboardOptions(keyboardType = keyboard),
            isError = error != null, supportingText = if (error != null) ({ Text(error) }) else null,
            colors = OutlinedTextFieldDefaults.colors(unfocusedBorderColor = OiColors.Green.copy(alpha = .5f)))
    }
}

@Composable
fun OiNotice(text: String) {
    Text(text, fontSize = 12.sp, lineHeight = 18.sp, color = OiColors.Dark,
        modifier = Modifier.fillMaxWidth().background(OiColors.Soft, RoundedCornerShape(10.dp)).padding(12.dp))
}
