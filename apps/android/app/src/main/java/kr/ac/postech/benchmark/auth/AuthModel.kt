package kr.ac.postech.benchmark.auth

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

data class AuthState(
    val loading: Boolean = true,
    val busy: Boolean = false,
    val pending: Boolean = false,
    val account: AuthAccount? = null,
    val error: String? = null,
    val configured: Boolean = true,
    val initializationFailed: Boolean = false
)

class AuthModel(application: Application) : AndroidViewModel(application) {
    private val service = (application as BenchmarkApplication).authService
    private val mutable = MutableStateFlow(AuthState(configured = service.configured))
    val state = mutable.asStateFlow()
    private val operation = Mutex()

    init { restore() }

    fun restore() {
        if (!service.configured) {
            mutable.value = AuthState(loading = false, configured = false,
                error = "Google 로그인 설정이 필요합니다. 관리자에게 문의해 주세요.")
        } else viewModelScope.launch {
            mutable.update { it.copy(loading = true, initializationFailed = false, error = null) }
            try {
                service.initialize()
                mutable.update { it.copy(pending = service.pending()) }
                service.sessions.collect { session ->
                    mutable.update { current -> when (session) {
                        AuthSession.Loading -> current.copy(loading = true)
                        AuthSession.SignedOut -> current.copy(loading = false, account = null)
                        AuthSession.Unavailable -> current.copy(loading = false, account = null,
                            error = "세션을 확인하지 못했습니다. 네트워크를 확인하고 다시 로그인해 주세요.")
                        is AuthSession.SignedIn -> current.copy(loading = false, account = session.account,
                            pending = false, error = null)
                    } }
                }
            } catch (error: CancellationException) { throw error }
            catch (_: Exception) {
                mutable.update { it.copy(loading = false, initializationFailed = true, error = "로그인 정보를 불러오지 못했습니다. 다시 시도해 주세요.") }
            }
        }
    }

    private fun perform(block: suspend () -> Unit) {
        if (!service.configured || mutable.value.busy || mutable.value.initializationFailed) return
        mutable.update { it.copy(busy = true, error = null) }
        viewModelScope.launch {
            operation.withLock {
                try { block() }
                catch (error: CancellationException) { throw error }
                catch (_: Exception) {
                    mutable.update { it.copy(error = "로그인 처리에 실패했습니다. 네트워크를 확인하고 다시 시도해 주세요.") }
                } finally { mutable.update { it.copy(busy = false) } }
            }
        }
    }

    fun beginGoogle(openBrowser: (Uri) -> Unit) = perform {
        if (mutable.value.account != null) return@perform
        service.initialize()
        val uri = service.beginGoogle()
        mutable.update { it.copy(pending = true) }
        try { openBrowser(uri) }
        catch (error: Exception) { service.cancel(); mutable.update { it.copy(pending = false) }; throw error }
    }

    fun callback(uri: Uri) {
        if (!AuthProtocol.isCallback(uri) || mutable.value.account != null) return
        perform {
            service.initialize()
            if (mutable.value.account != null) return@perform
            if (!service.pending() || AuthProtocol.code(uri) == null) {
                service.cancel()
                mutable.update { it.copy(pending = false, error = "로그인이 취소되었거나 만료되었습니다. 다시 시작해 주세요.") }
                return@perform
            }
            try { service.complete(uri) }
            finally { mutable.update { it.copy(pending = false) } }
        }
    }

    fun cancel() = perform { service.cancel(); mutable.update { it.copy(pending = false) } }
    fun signOut() = perform {
        try { service.signOut() }
        catch (error: CancellationException) { throw error }
        catch (_: Exception) {
            mutable.update { it.copy(error = "이 기기에서 로그아웃했습니다. 네트워크 오류로 서버의 세션 종료는 확인하지 못했습니다.") }
        }
        finally { mutable.update { it.copy(account = null, pending = false) } }
    }
}
