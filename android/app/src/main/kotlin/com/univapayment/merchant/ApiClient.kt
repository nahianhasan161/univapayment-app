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
        val text = call("POST", url, body.toString(), token)
        return if (text.isBlank()) JSONObject() else JSONObject(text)
    }

    private fun call(method: String, url: String, body: String?, token: String?): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 10_000
            connection.readTimeout = 15_000
            token?.let { connection.setRequestProperty("Authorization", "Bearer $it") }
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { it.write(body.toByteArray()) }
            }

            val status = connection.responseCode
            val stream = if (status < 400) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (status !in 200..299) {
                val message = runCatching { JSONObject(text).getJSONObject("error").getString("code") }
                    .getOrDefault("http_$status")
                throw ApiException(status, message)
            }
            return text
        } finally {
            connection.disconnect()
        }
    }

    /** The app's merchant screens. The token stays on this side and only reaches device routes. */
    fun request(context: Context, method: String, path: String, body: String?): String {
        require(path.startsWith("/api/v1/device/")) { "not a device route" }
        val session = DeviceSession(context)
        val token = session.token
        val base = session.serverUrl
        if (token == null || base == null) throw ApiException(401, "invalid_token")
        try {
            return call(method, base + path, body, token)
        } catch (e: ApiException) {
            if (e.status == 401) session.markRevoked()
            throw e
        }
    }

    /** Leaves the account on the server. Sends anything still waiting first, so no payment SMS is lost. */
    fun unpair(context: Context) {
        runCatching { sync(context) }
        try {
            request(context, "POST", "/api/v1/device/unpair", "{}")
        } catch (e: ApiException) {
            // Already removed from the dashboard: nothing left to do on the server.
            if (e.status != 401) throw e
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
                // A failure here must not make the SMS look unsent; the next sync tries again.
                runCatching { Notifier.check(context) }
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
                val body = c.getString(1).orEmpty()
                if (!SmsFilter.isAllowed(sender, body)) continue
                val sentAt = c.getLong(3).takeIf { it > 0 } ?: c.getLong(2)
                store.add(sender ?: "unknown", body, sentAt)
            }
        }
    }

    fun iso(millis: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date(millis))
}
