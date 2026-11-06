package com.mfsverify.mfs_merchant_app

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/** Senders the app may read. Every other SMS is ignored and never stored. */
object SmsFilter {
    private val allowedSenders = setOf("bkash", "nagad")

    fun isAllowed(sender: String?): Boolean =
        sender != null && sender.trim().lowercase() in allowedSenders
}

/** Local queue of captured SMS. In this prototype nothing leaves the phone. */
class SmsStore(context: Context) :
    SQLiteOpenHelper(context.applicationContext, "sms_probe.db", null, 1) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE captured (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sender TEXT NOT NULL,
                body TEXT NOT NULL,
                sms_time INTEGER NOT NULL,
                captured_at INTEGER NOT NULL
            )""",
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun insert(sender: String, body: String, smsTime: Long) {
        writableDatabase.insert(
            "captured",
            null,
            ContentValues().apply {
                put("sender", sender)
                put("body", body)
                put("sms_time", smsTime)
                put("captured_at", System.currentTimeMillis())
            },
        )
    }

    fun all(): List<Map<String, Any>> {
        val rows = mutableListOf<Map<String, Any>>()
        readableDatabase.query(
            "captured",
            arrayOf("sender", "body", "sms_time", "captured_at"),
            null, null, null, null,
            "id DESC",
        ).use { c ->
            while (c.moveToNext()) {
                rows += mapOf(
                    "sender" to c.getString(0),
                    "body" to c.getString(1),
                    "smsTime" to c.getLong(2),
                    "capturedAt" to c.getLong(3),
                )
            }
        }
        return rows
    }
}
