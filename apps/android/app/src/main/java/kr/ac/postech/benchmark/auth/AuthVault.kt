package kr.ac.postech.benchmark.auth

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.github.jan.supabase.auth.CodeVerifierCache
import io.github.jan.supabase.auth.SessionManager
import io.github.jan.supabase.auth.user.UserSession
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** App-private ciphertext; key material stays in Android Keystore. Backups are disabled. */
class AuthVault(context: Context) : SessionManager, CodeVerifierCache {
    private val preferences = context.getSharedPreferences("supabase_auth", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }
    private val alias = "benchmark.auth.v1"

    @Synchronized private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }

    @Synchronized private fun write(name: String, value: String?) {
        val encoded = value?.let {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            Base64.encodeToString(cipher.iv + cipher.doFinal(it.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
        }
        check(preferences.edit().putString(name, encoded).commit()) { "Secure storage write failed" }
    }

    @Synchronized private fun read(name: String): String? {
        val encoded = preferences.getString(name, null) ?: return null
        return try {
            val bytes = Base64.decode(encoded, Base64.NO_WRAP)
            require(bytes.size > 28)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            cipher.doFinal(bytes.copyOfRange(12, bytes.size)).toString(Charsets.UTF_8)
        } catch (_: java.security.GeneralSecurityException) {
            write(name, null)
            null
        } catch (_: IllegalArgumentException) {
            write(name, null)
            null
        }
    }

    override suspend fun saveSession(session: UserSession) = write("session", json.encodeToString(session))
    override suspend fun loadSession(): UserSession? = read("session")?.let {
        try { json.decodeFromString<UserSession>(it) }
        catch (_: kotlinx.serialization.SerializationException) { write("session", null); null }
    }
    override suspend fun deleteSession() = write("session", null)
    override suspend fun saveCodeVerifier(codeVerifier: String) = write("verifier", codeVerifier)
    override suspend fun loadCodeVerifier(): String? = read("verifier")
    override suspend fun deleteCodeVerifier() { write("verifier", null); write("started", null) }
    fun startedAt(): Long = read("started")?.toLongOrNull() ?: 0L
    fun markStarted() = write("started", System.currentTimeMillis().toString())
}
