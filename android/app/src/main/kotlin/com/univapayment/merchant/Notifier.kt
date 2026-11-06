package com.univapayment.merchant

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject

/**
 * Shows the server's new notifications on the phone. It runs after every SMS sync and every
 * periodic sync, so an SMS result appears at once and anything else within about 15 minutes.
 */
object Notifier {
    private const val CHANNEL = "payments"
    const val EXTRA_OPEN = "open_notifications"

    fun canNotify(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    fun check(context: Context) {
        val session = DeviceSession(context)
        val cursor = session.notifyCursor
        if (cursor == null) {
            // The first run after an update: only what happens from now on.
            session.notifyCursor = ApiClient.iso(System.currentTimeMillis())
            return
        }
        val text = ApiClient.request(context, "GET", "/api/v1/device/notifications?after=${java.net.URLEncoder.encode(cursor, "UTF-8")}", null)
        val rows = JSONObject(text).getJSONArray("notifications")
        if (rows.length() == 0) return
        // Newest first from the server.
        session.notifyCursor = rows.getJSONObject(0).getString("created_at")
        if (!canNotify(context)) return
        createChannel(context)
        for (i in rows.length() - 1 downTo 0) {
            val row = rows.getJSONObject(i)
            show(context, row.getString("id"), row.getString("title"), row.optString("body"))
        }
    }

    private fun show(context: Context, id: String, title: String, body: String) {
        val open = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(EXTRA_OPEN, true)
        val tap = PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(0xFF0F766E.toInt())
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(id.hashCode(), notification)
        } catch (_: SecurityException) {
            // The permission was withdrawn between the check and this call.
        }
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(CHANNEL, "পেমেন্ট", NotificationManager.IMPORTANCE_HIGH)
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
