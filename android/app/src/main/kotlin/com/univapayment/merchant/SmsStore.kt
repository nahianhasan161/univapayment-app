package com.univapayment.merchant

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.security.MessageDigest

object SmsFilter {
    private val allowedSenders = setOf("bkash", "nagad")

    private val testMessage = Regex("^\\s*UnivaPayment TEST [0-9A-Fa-f]{6}\\s*$", RegexOption.IGNORE_CASE)

    fun isPaymentSender(sender: String?): Boolean =
        sender != null && sender.trim().lowercase() in allowedSenders

    /** Sandbox SMS come from any number, so they are recognised by their exact text. */
    fun isTestMessage(body: String): Boolean = testMessage.matches(body)

    /** Every other SMS is ignored, never stored and never sent. */
    fun isAllowed(sender: String?, body: String): Boolean =
        isPaymentSender(sender) || isTestMessage(body)

    /** The same SMS gets the same id from the receiver and the inbox scan. */
    fun smsId(sender: String, body: String, sentAt: Long): String =
        MessageDigest.getInstance("SHA-256")
            .digest("${sender.trim().lowercase()}|$sentAt|$body".toByteArray())
            .joinToString("") { "%02x".format(it) }
}

data class QueuedSms(val id: String, val sender: String, val body: String, val smsTime: Long)

/** Keeps each SMS on the phone until the server has confirmed it. */
class SmsStore(context: Context) :
    SQLiteOpenHelper(context.applicationContext, "sms_queue.db", null, 1) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE queue (
                id TEXT PRIMARY KEY,
                sender TEXT NOT NULL,
                body TEXT NOT NULL,
                sms_time INTEGER NOT NULL,
                captured_at INTEGER NOT NULL,
                sent_at INTEGER
            )""",
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun add(sender: String, body: String, smsTime: Long) {
        writableDatabase.insertWithOnConflict(
            "queue",
            null,
            ContentValues().apply {
                put("id", SmsFilter.smsId(sender, body, smsTime))
                put("sender", sender.trim())
                put("body", body)
                put("sms_time", smsTime)
                put("captured_at", System.currentTimeMillis())
            },
            SQLiteDatabase.CONFLICT_IGNORE,
        )
    }

    fun unsent(limit: Int): List<QueuedSms> {
        val rows = mutableListOf<QueuedSms>()
        readableDatabase.query(
            "queue", arrayOf("id", "sender", "body", "sms_time"),
            "sent_at IS NULL", null, null, null, "sms_time ASC", limit.toString(),
        ).use { c ->
            while (c.moveToNext()) {
                rows += QueuedSms(c.getString(0), c.getString(1), c.getString(2), c.getLong(3))
            }
        }
        return rows
    }

    fun markSent(ids: List<String>) {
        val values = ContentValues().apply { put("sent_at", System.currentTimeMillis()) }
        writableDatabase.transaction {
            ids.forEach { update("queue", values, "id = ?", arrayOf(it)) }
        }
    }

    fun count(sent: Boolean): Int =
        readableDatabase.rawQuery(
            "SELECT COUNT(*) FROM queue WHERE sent_at IS ${if (sent) "NOT NULL" else "NULL"}",
            null,
        ).use { c -> c.moveToFirst(); c.getInt(0) }

    fun recent(limit: Int): List<Map<String, Any?>> {
        val rows = mutableListOf<Map<String, Any?>>()
        readableDatabase.query(
            "queue", arrayOf("sender", "body", "sms_time", "captured_at", "sent_at"),
            null, null, null, null, "sms_time DESC", limit.toString(),
        ).use { c ->
            while (c.moveToNext()) {
                rows += mapOf(
                    "sender" to c.getString(0),
                    "body" to c.getString(1),
                    "smsTime" to c.getLong(2),
                    "capturedAt" to c.getLong(3),
                    "sentAt" to if (c.isNull(4)) null else c.getLong(4),
                )
            }
        }
        return rows
    }

    fun clear() {
        writableDatabase.delete("queue", null, null)
    }

    private inline fun SQLiteDatabase.transaction(block: SQLiteDatabase.() -> Unit) {
        beginTransaction()
        try {
            block()
            setTransactionSuccessful()
        } finally {
            endTransaction()
        }
    }
}
