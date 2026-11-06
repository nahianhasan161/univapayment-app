package com.univapayment.merchant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import kotlin.concurrent.thread

/** Runs even when the app is closed, unless the user force-stopped it. */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        val first = parts.firstOrNull() ?: return
        val sender = first.originatingAddress
        if (!SmsFilter.isAllowed(sender)) return
        if (!DeviceSession(context).isPaired) return

        // A long SMS arrives in several parts.
        val body = parts.joinToString("") { it.messageBody.orEmpty() }
        val pending = goAsync()
        thread {
            try {
                SmsStore(context).use { it.add(sender!!, body, first.timestampMillis) }
                // Try right away, so the customer's wait is short; fall back to the worker.
                runCatching { ApiClient.sync(context) }
                    .onFailure { SyncWorker.enqueueNow(context) }
            } finally {
                pending.finish()
            }
        }
    }
}
