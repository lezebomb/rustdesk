package com.carriez.flutter_hbb

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * RemoteDesk local user verification, gating the saved Windows logon password.
 *
 * Only framework APIs are used, so `androidx.biometric` (and a dependency bump
 * for it) is not needed: [BiometricPrompt] on API 28+, with
 * [KeyguardManager.createConfirmDeviceCredentialIntent] (device PIN / pattern /
 * password) as the fallback for older devices or when no biometric is enrolled.
 *
 * One attempt at a time; every outcome answers the pending Dart call exactly
 * once. Nothing here logs the password or the prompt text beyond error codes.
 */
object RdBiometric {
    private const val TAG = "RdBiometric"
    private const val REQ_CREDENTIAL = 401

    const val KIND_BIOMETRIC = "biometric"
    const val KIND_CREDENTIAL = "credential"
    const val KIND_NONE = "none"

    private var pending: MethodChannel.Result? = null

    /** Returns true when [call] was handled. */
    fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method == "canAuthenticate") {
            result.success(canAuthenticate(activity))
            return true
        }
        if (call.method == "authenticate") {
            authenticate(activity, call, result)
            return true
        }
        return false
    }

    /** What kind of verification this device can offer right now. */
    fun canAuthenticate(context: Context): String {
        if (hasBiometricHardware(context)) return KIND_BIOMETRIC
        if (isDeviceSecure(context)) return KIND_CREDENTIAL
        return KIND_NONE
    }

    private fun hasBiometricHardware(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        val pm = context.packageManager
        if (pm.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (pm.hasSystemFeature(PackageManager.FEATURE_FACE)) return true
            if (pm.hasSystemFeature(PackageManager.FEATURE_IRIS)) return true
        }
        return false
    }

    private fun isDeviceSecure(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        return km?.isDeviceSecure == true
    }

    private fun authenticate(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        if (pending != null) {
            // A prompt is already up; do not stack a second one.
            result.success(false)
            return
        }
        if (activity.isFinishing) {
            result.success(false)
            return
        }
        val reason = call.argument<String>("reason") ?: "验证指纹以解锁远程电脑"
        when (canAuthenticate(activity)) {
            KIND_BIOMETRIC -> startBiometric(activity, reason, result)
            KIND_CREDENTIAL -> startCredential(activity, result)
            else -> result.success(false)
        }
    }

    @Suppress("DEPRECATION")
    private fun startBiometric(
        activity: Activity,
        reason: String,
        result: MethodChannel.Result
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            startCredential(activity, result)
            return
        }
        val signal = CancellationSignal()
        val prompt = BiometricPrompt.Builder(activity)
            .setTitle(reason)
            .setNegativeButton("取消", activity.mainExecutor) { _, _ -> finish(false) }
            .build()
        pending = result
        try {
            prompt.authenticate(signal, activity.mainExecutor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(
                        authResult: BiometricPrompt.AuthenticationResult
                    ) {
                        finish(true)
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        // Only the error code is recorded; errString is OS text.
                        Log.i(TAG, "biometric error $errorCode")
                        if (errorCode == BiometricPrompt.BIOMETRIC_ERROR_NO_BIOMETRICS ||
                            errorCode == BiometricPrompt.BIOMETRIC_ERROR_HW_UNAVAILABLE
                        ) {
                            // Hardware present but nothing enrolled: fall back to the
                            // device credential instead of failing the unlock.
                            pending = null
                            startCredential(activity, result)
                        } else {
                            finish(false)
                        }
                    }

                    override fun onAuthenticationFailed() {
                        // The system keeps the prompt open and lets the user retry;
                        // this is not an app-level retry.
                    }
                })
        } catch (e: Exception) {
            Log.i(TAG, "biometric prompt failed: ${e.javaClass.simpleName}")
            finish(false)
        }
    }

    @Suppress("DEPRECATION")
    private fun startCredential(activity: Activity, result: MethodChannel.Result) {
        val km = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val intent = if (km != null && km.isKeyguardSecure) {
            km.createConfirmDeviceCredentialIntent(
                "验证身份",
                "验证通过后发送电脑登录密码"
            )
        } else {
            null
        }
        if (intent == null) {
            result.success(false)
            return
        }
        pending = result
        try {
            activity.startActivityForResult(intent, REQ_CREDENTIAL)
        } catch (e: Exception) {
            Log.i(TAG, "credential intent failed: ${e.javaClass.simpleName}")
            finish(false)
        }
    }

    /** Forwarded from the activity; returns true when the result was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQ_CREDENTIAL) return false
        finish(resultCode == Activity.RESULT_OK)
        return true
    }

    private fun finish(ok: Boolean) {
        val r = pending ?: return
        pending = null
        r.success(ok)
    }
}
