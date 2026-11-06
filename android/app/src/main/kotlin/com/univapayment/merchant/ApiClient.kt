package com.univapayment.merchant

import android.content.Context
import android.os.Build
import android.provider.Telephony
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class ApiException(val status: Int, message: String) : Exception(message)

/** Talks to the UnivaPayment API, which writes to Supabase on the server. */
object ApiClient {
    private const val BATCH_SIZE = 50
    private val lock = Any()

    private fun post(url: String, body: JSONObject, token: String? = null): JSONObject {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 10_000
            connection.readTimeout = 15_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            token?.let { connection.setRequestProperty("Authorization", "Bearer $it") }
            connection.outputStream.use { it.write(body.toString().toByteArray()) }

            val status = connection.responseCode
            val stream = if (status < 400) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (status !in 200..299) {
                val message = runCatching { JSONObject(text).getJSONObject("error").getString("code") }
                    .getOrDefault("http_$status")
                throw ApiException(status, message)
            }
            return if (text.isBlank()) JSONObject() else JSONObject(text)
        } finally {
            connection.disconnect()
        }
    }

    fun pair(context: Context, serverUrl: String, code: String) {
        val base = serverUrl.trim().trimEnd('/')
        val response = post(
            "$base/api/v1/device/pair",
            JSONObject()
                .put("code", code.trim())
                .put("name", "${Build.MANUFACTURER} ${Build.MODEL}".take(100))
                .put("app_version", BuildConfig.VERSION_NAME),
        )
        val session = DeviceSession(context)
        session.save(base, response.getString("token"))
        SmsStore(context).use { it.clear() }
    }

    /** Sends everything waiting. Returns normally only when the queue has been handed over. */
    fun sync(context: Context) = synchronized(lock) {
        val session = DeviceSession(context)
        val token = session.token
        val base = session.serverUrl
        if (token == null || base == null || session.revoked) return@synchronized

        SmsStore(context).use { store ->
            collectMissed(context, session, store)
            try {
                var batch = store.unsent(BATCH_SIZE)
                if (batch.isEmpty()) {
                    post("$base/api/v1/device/heartbeat", JSONObject(), token)
                }
                while (batch.isNotEmpty()) {
                    val messages = JSONArray()
                    batch.forEach {
                        messages.put(
                            JSONObject()
                                .put("device_sms_id", it.id)
                                .put("sender", it.sender)
                                .put("body", it.body)
                                .put("sms_time", iso(it.smsTime)),
                        )
                    }
                    post("$base/api/v1/device/sms", JSONObject().put("messages", messages), token)
                    store.markSent(batch.map { it.id })
                    batch = store.unsent(BATCH_SIZE)
                }
                session.recordSync(null)
            } catch (e: ApiException) {
                if (e.status == 401) session.markRevoked()
                session.recordSync(e.message)
                throw e
            } catch (e: Exception) {
                session.recordSync("network")
                throw e
            }
        }
    }

    /** Picks up anything the receiver missed. Only SMS from after pairing, never older history. */
    private fun collectMissed(context: Context, session: DeviceSession, store: SmsStore) {
        val hasPermission = context.checkSelfPermission(android.Manifest.permission.READ_SMS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!hasPermission) return
        context.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE, Telephony.Sms.DATE_SENT),
            "${Telephony.Sms.DATE} >= ?",
            arrayOf(session.pairedAt.toString()),
            "${Telephony.Sms.DATE} ASC",
        )?.use { c ->
            while (c.moveToNext()) {
                val sender = c.getString(0)
                if (!SmsFilter.isAllowed(sender)) continue
                val sentAt = c.getLong(3).takeIf { it > 0 } ?: c.getLong(2)
                store.add(sender, c.getString(1).orEmpty(), sentAt)
            }
        }
    }

    private fun iso(millis: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date(millis))
}
