package kr.ac.postech.benchmark

import android.net.Uri
import kotlinx.coroutines.flow.MutableStateFlow
import kr.ac.postech.benchmark.auth.*

/** Authentication is replaced only in the local JVM test application. */
class NavigationTestApplication : BenchmarkApplication() {
    override fun createAuthService(): AuthService = object : AuthService {
        override val configured = true
        override val sessions = MutableStateFlow<AuthSession>(AuthSession.SignedIn(AuthAccount("navigation-test", null)))
        override suspend fun initialize() = Unit
        override suspend fun pending() = false
        override suspend fun beginGoogle(): Uri = error("Navigation tests do not launch OAuth")
        override suspend fun complete(uri: Uri) = error("Navigation tests do not accept callbacks")
        override suspend fun cancel() = Unit
        override suspend fun signOut() { sessions.value = AuthSession.SignedOut }
    }
}
