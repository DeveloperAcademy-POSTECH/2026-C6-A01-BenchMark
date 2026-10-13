package kr.ac.postech.benchmark

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import kr.ac.postech.benchmark.auth.AuthModel

class MainActivity : ComponentActivity() {
    private val auth: AuthModel by viewModels { ViewModelProvider.AndroidViewModelFactory(application) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        consumeCallback(intent)
        setContent {
            val state by auth.state.collectAsState()
            var showLogin by rememberSaveable { mutableStateOf(false) }
            var pendingRoute by rememberSaveable { mutableStateOf<String?>(null) }
            var pendingBench by rememberSaveable { mutableIntStateOf(1) }
            val account = state.account
            LaunchedEffect(account?.id) { if (account != null) showLogin = false }
            BackHandler(showLogin) { showLogin = false; pendingRoute = null; if (!state.busy) auth.cancel() }
            OiTheme {
                if (!showLogin || account != null) {
                    key(account?.id ?: "guest") {
                        val model: LofiModel = viewModel(key = "lofi-${account?.id ?: "guest"}")
                        BenchmarkApp(model, signedIn = account != null,
                            login = { route -> pendingRoute = route.name; pendingBench = model.state.bench; showLogin = true },
                            pendingRoute = pendingRoute?.let { name -> Screen.entries.firstOrNull { it.name == name } },
                            pendingBench = pendingBench,
                            pendingConsumed = { pendingRoute = null },
                            signOut = { model.reset(); showLogin = false; pendingRoute = null; auth.signOut() })
                    }
                } else Surface(modifier = Modifier.safeDrawingPadding()) {
                    Page {
                        TextButton({ showLogin = false; pendingRoute = null; if (!state.busy) auth.cancel() }, Modifier.testTag("close-login")) { Text("홈으로 돌아가기") }
                        OiHeader()
                        Heading("로그인")
                        Text("Google 계정으로 로그인해 주세요.")
                        if (state.loading || state.busy) CircularProgressIndicator()
                        state.error?.let { Text(it, color = MaterialTheme.colorScheme.error,
                            modifier = Modifier.testTag("auth-error")) }
                        if (state.initializationFailed) {
                            Button(onClick = auth::restore) { Text("다시 시도") }
                        } else if (state.pending) {
                            Text("브라우저에서 로그인을 완료해 주세요.")
                            TextButton(onClick = auth::cancel, enabled = !state.busy) { Text("로그인 취소") }
                        } else Button(onClick = {
                            auth.beginGoogle { uri -> CustomTabsIntent.Builder().build().launchUrl(this@MainActivity, uri) }
                        }, enabled = state.configured && !state.loading && !state.busy,
                            modifier = Modifier.testTag("google-login")) { Text("Google로 계속하기") }
                        Text("본인인증·기부 접수는 아직 화면 예시입니다.", Modifier.padding(top = 12.dp))
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeCallback(intent)
    }

    private fun consumeCallback(intent: Intent?) {
        val uri = intent?.data ?: return
        intent.data = null
        auth.callback(uri)
    }
}
