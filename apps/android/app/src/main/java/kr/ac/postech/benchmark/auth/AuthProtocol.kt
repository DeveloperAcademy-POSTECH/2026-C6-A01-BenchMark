package kr.ac.postech.benchmark.auth

import android.net.Uri
import android.util.Base64
import java.security.MessageDigest
import java.security.SecureRandom

object AuthProtocol {
    const val CALLBACK = "kr.ac.postech.benchmark://auth/callback"
    const val ATTEMPT_LIFETIME_MS = 15 * 60 * 1000L

    fun newVerifier(): String = Base64.encodeToString(ByteArray(32).also { SecureRandom().nextBytes(it) },
        Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)

    fun challenge(verifier: String): String = Base64.encodeToString(
        MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII)),
        Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)

    fun authorizationUrl(baseUrl: String, verifier: String): Uri = Uri.parse("$baseUrl/auth/v1/authorize")
        .buildUpon().appendQueryParameter("provider", "google")
        .appendQueryParameter("redirect_to", CALLBACK)
        .appendQueryParameter("code_challenge", challenge(verifier))
        .appendQueryParameter("code_challenge_method", "s256")
        .appendQueryParameter("scopes", "openid email profile").build()

    fun isCallback(uri: Uri): Boolean = uri.scheme == "kr.ac.postech.benchmark" &&
        uri.host == "auth" && uri.path == "/callback" && uri.port == -1 && uri.userInfo == null

    fun code(uri: Uri): String? {
        if (!isCallback(uri) || uri.fragment != null || uri.getQueryParameter("error") != null) return null
        val codes = uri.getQueryParameters("code")
        return codes.singleOrNull()?.takeIf { it.isNotBlank() && it.length <= 4096 }
    }

    fun pendingValid(startedAt: Long, now: Long): Boolean =
        startedAt > 0 && now >= startedAt && now - startedAt < ATTEMPT_LIFETIME_MS
}
