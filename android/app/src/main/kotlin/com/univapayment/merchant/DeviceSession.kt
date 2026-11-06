package com.univapayment.merchant

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Pairing state. The device token is encrypted with a key held in Android Keystore. */
class DeviceSession(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("device_session", Context.MODE_PRIVATE)

    val isPaired: Boolean get() = prefs.contains(KEY_TOKEN)
    val serverUrl: String? get() = prefs.getString(KEY_URL, null)
    val pairedAt: Long get() = prefs.getLong(KEY_PAIRED_AT, 0)
    val lastSyncAt: Long get() = prefs.getLong(KEY_LAST_SYNC, 0)
    val lastError: String? get() = prefs.getString(KEY_LAST_ERROR, null)
    val revoked: Boolean get() = prefs.getBoolean(KEY_REVOKED, false)

    val token: String?
        get() = prefs.getString(KEY_TOKEN, null)?.let { sealed ->
            runCatching {
                val raw = Base64.decode(sealed, Base64.NO_WRAP)
                val cipher = Cipher.getInstance(TRANSFORM)
                cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, raw, 0, IV_SIZE))
                String(cipher.doFinal(raw, IV_SIZE, raw.size - IV_SIZE))
            }.getOrNull()
        }

    fun save(serverUrl: String, token: String) {
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(token.toByteArray())
        prefs.edit()
            .putString(KEY_URL, serverUrl)
            .putString(KEY_TOKEN, Base64.encodeToString(sealed, Base64.NO_WRAP))
            .putLong(KEY_PAIRED_AT, System.currentTimeMillis())
            .putBoolean(KEY_REVOKED, false)
            .remove(KEY_LAST_ERROR)
            .apply()
    }

    fun recordSync(error: String?) {
        prefs.edit().apply {
            if (error == null) {
                putLong(KEY_LAST_SYNC, System.currentTimeMillis())
                remove(KEY_LAST_ERROR)
            } else {
                putString(KEY_LAST_ERROR, error)
            }
        }.apply()
    }

    fun markRevoked() = prefs.edit().putBoolean(KEY_REVOKED, true).apply()

    fun clear() = prefs.edit().clear().apply()

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(
                KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build(),
            )
            generateKey()
        }
    }

    private companion object {
        const val KEY_ALIAS = "univapayment_device"
        const val TRANSFORM = "AES/GCM/NoPadding"
        const val IV_SIZE = 12
        const val KEY_URL = "server_url"
        const val KEY_TOKEN = "token"
        const val KEY_PAIRED_AT = "paired_at"
        const val KEY_LAST_SYNC = "last_sync"
        const val KEY_LAST_ERROR = "last_error"
        const val KEY_REVOKED = "revoked"
    }
}
