package com.mfsverify.mfs_merchant_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/** Runs even when the app is closed, unless the user force-stopped it. */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        val first = parts.firstOrNull() ?: return
        val sender = first.originatingAddress
        if (!SmsFilter.isAllowed(sender)) return

        // A long SMS arrives in several parts.
        val body = parts.joinToString("") { it.messageBody.orEmpty() }
        SmsStore(context).use { it.insert(sender!!.trim(), body, first.timestampMillis) }
    }
}
