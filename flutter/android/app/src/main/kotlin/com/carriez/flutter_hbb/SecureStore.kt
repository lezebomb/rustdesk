package com.carriez.flutter_hbb

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Credential storage for RemoteDesk.
 *
 * The AES-256-GCM key lives in AndroidKeyStore and cannot be exported; only the
 * ciphertext + IV are written to shared preferences. Nothing secret is logged.
 */
object SecureStore {
    private const val TAG = "RdSecureStore"
    private const val KEY_ALIAS = "remotedesk_credentials_v1"
    private const val PREFS = "remotedesk_secure"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_BITS = 128
    private const val IV_LEN = 12

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun getOrCreateKey(): SecretKey {
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE)
        ks.load(null)
        val existing = ks.getEntry(KEY_ALIAS, null)
        if (existing is KeyStore.SecretKeyEntry) {
            return existing.secretKey
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    fun put(context: Context, key: String, value: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val iv = cipher.iv
        val cipherText = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val blob = ByteArray(iv.size + cipherText.size)
        System.arraycopy(iv, 0, blob, 0, iv.size)
        System.arraycopy(cipherText, 0, blob, iv.size, cipherText.size)
        prefs(context).edit()
            .putString(key, Base64.encodeToString(blob, Base64.NO_WRAP))
            .apply()
    }

    fun get(context: Context, key: String): String? {
        val encoded = prefs(context).getString(key, null) ?: return null
        return try {
            val blob = Base64.decode(encoded, Base64.NO_WRAP)
            if (blob.size <= IV_LEN) return null
            val iv = blob.copyOfRange(0, IV_LEN)
            val cipherText = blob.copyOfRange(IV_LEN, blob.size)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                getOrCreateKey(),
                GCMParameterSpec(GCM_TAG_BITS, iv)
            )
            String(cipher.doFinal(cipherText), Charsets.UTF_8)
        } catch (e: Exception) {
            // A rotated/cleared keystore makes old ciphertext unreadable; drop it
            // so the user is asked for the password again instead of crashing.
            Log.w(TAG, "decrypt failed: ${e.javaClass.simpleName}")
            prefs(context).edit().remove(key).apply()
            null
        }
    }

    fun delete(context: Context, key: String) {
        prefs(context).edit().remove(key).apply()
    }

    /** Returns true when the call was handled. */
    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result): Boolean {
        val key = call.argument<String>("key")
        if (key.isNullOrEmpty()) {
            result.error("bad_args", "missing key", null)
            return true
        }
        try {
            when (call.method) {
                "put" -> {
                    val value = call.argument<String>("value") ?: ""
                    put(context, key, value)
                    result.success(true)
                }
                "get" -> result.success(get(context, key))
                "delete" -> {
                    delete(context, key)
                    result.success(true)
                }
                else -> return false
            }
        } catch (e: Exception) {
            Log.e(TAG, "operation failed: ${e.javaClass.simpleName}")
            result.error("keystore_error", e.javaClass.simpleName, null)
        }
        return true
    }
}
