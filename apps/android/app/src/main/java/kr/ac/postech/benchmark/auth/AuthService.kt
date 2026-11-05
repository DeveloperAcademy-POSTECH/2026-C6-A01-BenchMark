package kr.ac.postech.benchmark.auth

import android.app.Application
import android.net.Uri
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.FlowType
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.createSupabaseClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kr.ac.postech.benchmark.BuildConfig

data class AuthAccount(val id: String, val email: String?)
sealed interface AuthSession {
    data object Loading : AuthSession
    data object SignedOut : AuthSession
    data object Unavailable : AuthSession
    data class SignedIn(val account: AuthAccount) : AuthSession
}

interface AuthService {
    val configured: Boolean
    val sessions: Flow<AuthSession>
    suspend fun initialize()
    suspend fun pending(): Boolean
    suspend fun beginGoogle(): Uri
    suspend fun complete(uri: Uri)
    suspend fun cancel()
    suspend fun signOut()
}

open class BenchmarkApplication : Application() {
    val authService: AuthService by lazy { createAuthService() }
    protected open fun createAuthService(): AuthService = SupabaseAuthService(this)
}

private class SupabaseAuthService(application: Application) : AuthService {
    override val configured = BuildConfig.SUPABASE_PUBLISHABLE_KEY.isNotBlank()
    private val vault = AuthVault(application)
    private val client by lazy {
        createSupabaseClient(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_PUBLISHABLE_KEY) {
            install(Auth) {
                flowType = FlowType.PKCE
                sessionManager = vault
                codeVerifierCache = vault
                defaultRedirectUrl = AuthProtocol.CALLBACK
            }
        }
    }
    override val sessions: Flow<AuthSession> get() = client.auth.sessionStatus.map { status ->
        when (status) {
            SessionStatus.Initializing -> AuthSession.Loading
            is SessionStatus.NotAuthenticated -> AuthSession.SignedOut
            is SessionStatus.RefreshFailure -> AuthSession.Unavailable
            is SessionStatus.Authenticated -> status.session.user?.let {
                AuthSession.SignedIn(AuthAccount(it.id, it.email))
            } ?: AuthSession.Unavailable
        }
    }
    override suspend fun initialize() = client.auth.awaitInitialization()
    override suspend fun pending(): Boolean {
        val valid = AuthProtocol.pendingValid(vault.startedAt(), System.currentTimeMillis()) &&
            vault.loadCodeVerifier() != null
        if (!valid) vault.deleteCodeVerifier()
        return valid
    }
    override suspend fun beginGoogle(): Uri {
        val verifier = AuthProtocol.newVerifier()
        vault.saveCodeVerifier(verifier)
        vault.markStarted()
        return AuthProtocol.authorizationUrl(BuildConfig.SUPABASE_URL, verifier)
    }
    override suspend fun complete(uri: Uri) {
        check(pending())
        val code = requireNotNull(AuthProtocol.code(uri))
        try {
            client.auth.exchangeCodeForSession(code)
        } finally {
            vault.deleteCodeVerifier()
        }
    }
    override suspend fun cancel() = vault.deleteCodeVerifier()
    override suspend fun signOut() {
        try { client.auth.signOut() }
        finally { client.auth.clearSession() }
    }
}
