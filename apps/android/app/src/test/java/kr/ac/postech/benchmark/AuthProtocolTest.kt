package kr.ac.postech.benchmark

import android.net.Uri
import kr.ac.postech.benchmark.auth.AuthProtocol
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AuthProtocolTest {
    @Test fun rfc7636ChallengeAndAuthorizationRequest() {
        val verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        assertEquals("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", AuthProtocol.challenge(verifier))
        val uri = AuthProtocol.authorizationUrl("https://example.supabase.co", verifier)
        assertEquals("google", uri.getQueryParameter("provider"))
        assertEquals(AuthProtocol.CALLBACK, uri.getQueryParameter("redirect_to"))
        assertEquals("s256", uri.getQueryParameter("code_challenge_method"))
        assertFalse(uri.toString().contains(verifier))
        val generated = List(100) { AuthProtocol.newVerifier() }
        assertEquals(100, generated.toSet().size)
        assertTrue(generated.all { it.matches(Regex("[A-Za-z0-9_-]{43}")) })
    }
    @Test fun rejectsUnexpectedAndAmbiguousCallbacks() {
        assertEquals("test-code", AuthProtocol.code(Uri.parse("${AuthProtocol.CALLBACK}?code=test-code")))
        listOf(
            "https://auth/callback?code=x", "kr.ac.postech.benchmark://evil/callback?code=x",
            "kr.ac.postech.benchmark://auth:99/callback?code=x", "kr.ac.postech.benchmark://user@auth/callback?code=x",
            "${AuthProtocol.CALLBACK}/extra?code=x", "${AuthProtocol.CALLBACK}?code=x&code=y",
            "${AuthProtocol.CALLBACK}?code=", "${AuthProtocol.CALLBACK}?code=x#error=token",
            "${AuthProtocol.CALLBACK}?code=x&error=access_denied", "${AuthProtocol.CALLBACK}#access_token=untrusted"
        ).forEach { assertNull(it, AuthProtocol.code(Uri.parse(it))) }
    }
    @Test fun pendingAttemptExpiresAndRejectsClockRollback() {
        assertTrue(AuthProtocol.pendingValid(100, 101))
        assertFalse(AuthProtocol.pendingValid(0, 101))
        assertFalse(AuthProtocol.pendingValid(100, 99))
        assertFalse(AuthProtocol.pendingValid(100, 100 + AuthProtocol.ATTEMPT_LIFETIME_MS))
    }
}
