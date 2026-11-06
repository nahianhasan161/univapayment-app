package com.univapayment.merchant

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
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val smsPermissions =
        arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_SMS)
    private var pendingPermission: MethodChannel.Result? = null
    private var openNotifications = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        openNotifications = intent?.getBooleanExtra(Notifier.EXTRA_OPEN, false) == true
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(Notifier.EXTRA_OPEN, false)) openNotifications = true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "univapayment/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(status())
                    "requestPermissions" -> requestSmsPermissions(result)
                    "pair" -> onBackground(result) {
                        ApiClient.pair(this, call.argument<String>("url")!!, call.argument<String>("code")!!)
                        SyncWorker.schedulePeriodic(this)
                        null
                    }
                    "syncNow" -> onBackground(result) {
                        ApiClient.sync(this)
                        null
                    }
                    "unpair" -> {
                        SyncWorker.cancelAll(this)
                        DeviceSession(this).clear()
                        SmsStore(this).use { it.clear() }
                        result.success(null)
                    }
                    "scanInbox" -> {
                        if (hasPermissions()) {
                            result.success(scanInbox(call.argument<Int>("limit") ?: 500))
                        } else {
                            result.error("NO_PERMISSION", "SMS permission missing", null)
                        }
                    }
                    "requestNotifications" -> requestNotifications(result)
                    "api" -> onBackground(result) {
                        ApiClient.request(this, call.argument<String>("method")!!, call.argument<String>("path")!!, call.argument<String>("body"))
                    }
                    "checkNotifications" -> onBackground(result) {
                        Notifier.check(this)
                        null
                    }
                    "recent" -> result.success(SmsStore(this).use { it.recent(20) })
                    "openBatterySettings" -> {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        if (DeviceSession(this).isPaired) SyncWorker.schedulePeriodic(this)
    }

    private fun onBackground(result: MethodChannel.Result, work: () -> Any?) {
        thread {
            try {
                val value = work()
                runOnUiThread { result.success(value) }
            } catch (e: ApiException) {
                runOnUiThread { result.error(e.message ?: "api_error", e.message, e.status) }
            } catch (e: Exception) {
                runOnUiThread { result.error("network", e.message, null) }
            }
        }
    }

    private fun status(): Map<String, Any?> {
        val session = DeviceSession(this)
        val (sent, unsent) = SmsStore(this).use { it.count(true) to it.count(false) }
        return mapOf(
            "permitted" to hasPermissions(),
            "notificationsAllowed" to Notifier.canNotify(this),
            "openNotifications" to openNotifications.also { openNotifications = false },
            "paired" to session.isPaired,
            "serverUrl" to session.serverUrl,
            "lastSyncAt" to session.lastSyncAt,
            "lastError" to session.lastError,
            "revoked" to session.revoked,
            "sent" to sent,
            "unsent" to unsent,
        )
    }

    private fun hasPermissions() = smsPermissions.all {
        ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotifications(result: MethodChannel.Result) {
        if (Notifier.canNotify(this) || android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
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
        if (requestCode == NOTIFICATION_REQUEST) {
            pendingPermission?.success(Notifier.canNotify(this))
            pendingPermission = null
        } else if (requestCode == PERMISSION_REQUEST) {
            pendingPermission?.success(hasPermissions())
            pendingPermission = null
        }
    }

    private fun scanInbox(limit: Int): List<Map<String, Any>> {
        val rows = mutableListOf<Map<String, Any>>()
        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY),
            null, null,
            "${Telephony.Sms.DATE} DESC",
        )?.use { c ->
            while (c.moveToNext() && rows.size < limit) {
                val sender = c.getString(0)
                if (!SmsFilter.isPaymentSender(sender)) continue
                rows += mapOf("sender" to sender.trim(), "body" to (c.getString(1) ?: ""))
            }
        }
        return rows
    }

    private companion object {
        const val PERMISSION_REQUEST = 4101
        const val NOTIFICATION_REQUEST = 4102
    }
}
