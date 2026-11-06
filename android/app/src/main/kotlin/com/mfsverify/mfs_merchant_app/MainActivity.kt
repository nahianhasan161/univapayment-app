package com.mfsverify.mfs_merchant_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val smsPermissions =
        arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_SMS)
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sms_probe")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermissions" -> result.success(hasPermissions())
                    "requestPermissions" -> requestSmsPermissions(result)
                    "scanInbox" -> {
                        if (hasPermissions()) {
                            result.success(scanInbox(call.argument<Int>("limit") ?: 500))
                        } else {
                            result.error("NO_PERMISSION", "SMS permission missing", null)
                        }
                    }
                    "captured" -> result.success(SmsStore(this).use { it.all() })
                    "openBatterySettings" -> {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasPermissions() = smsPermissions.all {
        ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestSmsPermissions(result: MethodChannel.Result) {
        if (hasPermissions()) {
            result.success(true)
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(this, smsPermissions, PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST) {
            pendingPermission?.success(hasPermissions())
            pendingPermission = null
        }
    }

    private fun scanInbox(limit: Int): List<Map<String, Any>> {
        val rows = mutableListOf<Map<String, Any>>()
        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
            null, null,
            "${Telephony.Sms.DATE} DESC",
        )?.use { c ->
            while (c.moveToNext() && rows.size < limit) {
                val sender = c.getString(0)
                if (!SmsFilter.isAllowed(sender)) continue
                rows += mapOf(
                    "sender" to sender.trim(),
                    "body" to (c.getString(1) ?: ""),
                    "smsTime" to c.getLong(2),
                )
            }
        }
        return rows
    }

    private companion object {
        const val PERMISSION_REQUEST = 4101
    }
}
