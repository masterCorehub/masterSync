package com.nexus.mastersync.services

import android.Manifest
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.provider.ContactsContract
import android.provider.Telephony
import android.telephony.SmsManager

/** The phone's SMS box and the SMS radio, behind the permissions the user granted. */
class SmsStore(private val context: Context) {
    private val names = HashMap<String, String?>()

    private fun granted(permission: String) = context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    fun canRead() = granted(Manifest.permission.READ_SMS)
    fun canSend() = granted(Manifest.permission.SEND_SMS)

    /** The contact's name for a number, or null (also when contacts were not allowed). */
    fun name(address: String): String? {
        if (!granted(Manifest.permission.READ_CONTACTS) || !SmsAddress.canSendTo(address)) return null
        return names.getOrPut(address) {
            runCatching {
                val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(address))
                context.contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) it.getString(0) else null
                }
            }.getOrNull()
        }
    }

    private fun rows(selection: String?, args: Array<String>?, limit: Int, offset: Int): List<SmsRow> {
        val query = Bundle().apply {
            if (selection != null) putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
            if (args != null) putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, args)
            putStringArray(ContentResolver.QUERY_ARG_SORT_COLUMNS, arrayOf(Telephony.Sms.DATE))
            putInt(ContentResolver.QUERY_ARG_SORT_DIRECTION, ContentResolver.QUERY_SORT_DIRECTION_DESCENDING)
            putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
            putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
        }
        val columns = arrayOf(Telephony.Sms._ID, Telephony.Sms.THREAD_ID, Telephony.Sms.ADDRESS, Telephony.Sms.BODY,
            Telephony.Sms.DATE, Telephony.Sms.TYPE, Telephony.Sms.READ)
        return runCatching {
            context.contentResolver.query(Telephony.Sms.CONTENT_URI, columns, query, null)?.use { read(it) }.orEmpty()
        }.getOrDefault(emptyList())
    }

    private fun read(cursor: Cursor): List<SmsRow> {
        val out = ArrayList<SmsRow>()
        while (cursor.moveToNext()) {
            out += SmsRow(cursor.getLong(0), cursor.getLong(1), cursor.getString(2).orEmpty(), cursor.getString(3).orEmpty(),
                cursor.getLong(4), cursor.getInt(5), cursor.getInt(6) != 0)
        }
        return out
    }

    /** Conversations, newest first. The newest 1500 messages are grouped, then paged. */
    fun threads(offset: Int, limit: Int): Pair<List<SmsThreadInfo>, Boolean> {
        val all = SmsGrouping.threads(rows(null, null, 1500, 0))
        return all.drop(offset).take(limit) to (all.size > offset + limit)
    }

    /** Messages of one conversation, newest first. */
    fun messages(threadId: Long, offset: Int, limit: Int): Pair<List<SmsEntryJson>, Boolean> {
        val found = rows("${Telephony.Sms.THREAD_ID} = ?", arrayOf(threadId.toString()), limit + 1, offset)
        return found.take(limit).map(SmsGrouping::entry) to (found.size > limit)
    }

    /** Sends [text] to [address]; the result is what to tell the Mac. */
    fun send(address: String, text: String): Pair<Boolean, String> {
        if (!canSend()) return false to "Autorize o envio de SMS no MasterSync do Android."
        return runCatching {
            val manager = context.getSystemService(SmsManager::class.java)
            val parts = manager.divideMessage(text)
            if (parts.size > 1) manager.sendMultipartTextMessage(SmsAddress.clean(address), null, parts, null, null)
            else manager.sendTextMessage(SmsAddress.clean(address), null, text, null, null)
            true to "SMS enviado."
        }.getOrElse { false to "O Android não conseguiu enviar o SMS." }
    }

    /** The messages in a received-SMS broadcast, one entry per sender. */
    fun fromIntent(intent: Intent): List<SmsEntryJson> {
        val parts = runCatching { Telephony.Sms.Intents.getMessagesFromIntent(intent) }.getOrNull().orEmpty()
        return parts.groupBy { it.originatingAddress.orEmpty() }.map { (address, group) ->
            val thread = runCatching { Telephony.Threads.getOrCreateThreadId(context, address).toString() }.getOrDefault("0")
            SmsEntryJson("in-${group.first().timestampMillis}-${address.hashCode()}", thread, address,
                SmsText.body(group.joinToString("") { it.messageBody.orEmpty() }), group.first().timestampMillis, outgoing = false)
        }
    }
}
