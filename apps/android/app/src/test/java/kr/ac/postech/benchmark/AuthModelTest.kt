package kr.ac.postech.benchmark

import android.net.Uri
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import kr.ac.postech.benchmark.auth.*
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

class AuthTestApplication : BenchmarkApplication() {
    val fake = FakeAuthService()
    override fun createAuthService(): AuthService = fake
}

class FakeAuthService : AuthService {
    override val configured = true
    override val sessions = MutableStateFlow<AuthSession>(AuthSession.SignedOut)
    var waiting = false
    var completed = 0
    var failExchange = false
    override suspend fun initialize() = Unit
    override suspend fun pending() = waiting
    override suspend fun beginGoogle(): Uri { waiting = true; return Uri.parse("https://example.supabase.co/auth/v1/authorize") }
    override suspend fun complete(uri: Uri) {
        waiting = false
        if (failExchange) error("Network unavailable")
        completed++
        sessions.value = AuthSession.SignedIn(AuthAccount("user-$completed", null))
    }
    override suspend fun cancel() { waiting = false }
    override suspend fun signOut() { sessions.value = AuthSession.SignedOut }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = AuthTestApplication::class)
class AuthModelTest {
    private lateinit var model: AuthModel
    private lateinit var service: FakeAuthService
    private fun flush() { shadowOf(Looper.getMainLooper()).idle() }
    @Before fun setup() {
        val app = ApplicationProvider.getApplicationContext<AuthTestApplication>()
        service = app.fake
        model = AuthModel(app)
        flush()
    }
    private fun start() { model.beginGoogle {}; flush() }
    private fun callback() { model.callback(Uri.parse("${AuthProtocol.CALLBACK}?code=valid-code")); flush() }

    @Test fun requiresAnInitiatedFlowAndRejectsReplay() {
        callback()
        assertEquals(0, service.completed)
        assertNull(model.state.value.account)
        start(); callback()
        assertEquals("user-1", model.state.value.account?.id)
        callback()
        assertEquals(1, service.completed)
    }
    @Test fun cancellationAndExchangeFailureStaySignedOut() {
        start(); model.cancel(); flush(); callback()
        assertNull(model.state.value.account)
        service.failExchange = true
        start(); callback()
        assertNull(model.state.value.account)
        assertFalse(model.state.value.pending)
        assertNotNull(model.state.value.error)
    }
    @Test fun browserFailureClearsPendingAttempt() {
        model.beginGoogle { error("No browser") }; flush()
        assertFalse(service.waiting)
        assertFalse(model.state.value.pending)
        assertNotNull(model.state.value.error)
    }
    @Test fun logoutAndAccountChangeUseNewIdentity() {
        start(); callback()
        model.signOut(); flush()
        assertNull(model.state.value.account)
        start(); callback()
        assertEquals("user-2", model.state.value.account?.id)
    }
}
