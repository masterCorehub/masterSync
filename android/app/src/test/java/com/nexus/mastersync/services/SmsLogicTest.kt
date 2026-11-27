package com.nexus.mastersync.services

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SmsLogicTest {
    private fun row(id: Long, thread: Long, address: String, body: String, date: Long, type: Int, read: Boolean = true) =
        SmsRow(id, thread, address, body, date, type, read)

    @Test fun groupsRowsIntoThreadsNewestFirst() {
        val threads = SmsGrouping.threads(listOf(
            row(1, 10, "+5511999990000", "oi", 1000, SmsRow.INBOX),
            row(2, 10, "+5511999990000", "tudo bem?", 3000, SmsRow.SENT),
            row(3, 20, "29104", "Seu código é 482913", 2000, SmsRow.INBOX, read = false),
        ))
        assertEquals(listOf("10", "20"), threads.map { it.id })
        assertEquals("tudo bem?", threads[0].snippet)
        assertEquals(3000L, threads[0].date)
        assertEquals(2, threads[0].count)
        assertEquals(0, threads[0].unread)
        assertEquals(1, threads[1].unread)
    }

    @Test fun onlyIncomingUnreadMessagesCountAsUnread() {
        val threads = SmsGrouping.threads(listOf(
            row(1, 1, "123456", "a", 1, SmsRow.SENT, read = false),
            row(2, 1, "123456", "b", 2, SmsRow.INBOX, read = false),
            row(3, 1, "123456", "c", 3, SmsRow.INBOX, read = true),
        ))
        assertEquals(1, threads.single().unread)
    }

    @Test fun threadAddressComesFromTheNewestMessage() {
        val threads = SmsGrouping.threads(listOf(
            row(1, 5, "+55 11 1111-1111", "x", 1, SmsRow.INBOX),
            row(2, 5, "+5511222222222", "y", 2, SmsRow.INBOX),
        ))
        assertEquals("+5511222222222", threads.single().address)
    }

    @Test fun emptyInputGivesNoThreads() = assertTrue(SmsGrouping.threads(emptyList()).isEmpty())

    @Test fun entryMarksOutgoingByType() {
        assertTrue(SmsGrouping.entry(row(1, 1, "1234", "a", 1, SmsRow.SENT)).outgoing)
        assertTrue(SmsGrouping.entry(row(1, 1, "1234", "a", 1, SmsRow.OUTBOX)).outgoing)
        assertFalse(SmsGrouping.entry(row(1, 1, "1234", "a", 1, SmsRow.INBOX)).outgoing)
    }

    @Test fun onlyRealPhoneNumbersCanReceiveASend() {
        assertTrue(SmsAddress.canSendTo("+5511999990000"))
        assertTrue(SmsAddress.canSendTo("(11) 99999-0000"))
        assertTrue(SmsAddress.canSendTo("29104"))
        assertFalse(SmsAddress.canSendTo("NUBANK"))
        assertFalse(SmsAddress.canSendTo(""))
        assertFalse(SmsAddress.canSendTo("12"))
        assertFalse(SmsAddress.canSendTo("+55 11 99999-0000; DROP"))
        assertFalse(SmsAddress.canSendTo("1".repeat(40)))
    }

    @Test fun cleanedNumberKeepsOnlyDigitsAndPlus() {
        assertEquals("+5511999990000", SmsAddress.clean("+55 (11) 99999-0000"))
        assertEquals("11999990000", SmsAddress.clean("(11) 99999-0000"))
    }

    @Test fun outgoingTextIsValidatedAndBounded() {
        assertEquals("oi", SmsText.outgoing("  oi  "))
        assertNull(SmsText.outgoing(""))
        assertNull(SmsText.outgoing("   \n "))
        assertNull(SmsText.outgoing("x".repeat(SmsText.MAX_OUTGOING + 1)))
        assertEquals(SmsText.MAX_OUTGOING, SmsText.outgoing("x".repeat(SmsText.MAX_OUTGOING))?.length)
    }

    @Test fun incomingBodiesAreTrimmedForThePhoneToMac() {
        assertEquals(SmsText.MAX_BODY, SmsText.body("y".repeat(5000)).length)
        assertEquals("olá", SmsText.body("olá"))
    }

    @Test fun pagesStayUnderTheFrameLimit() {
        val rows = List(500) { SmsEntryJson(it.toString(), "1", "+5511999990000", "z".repeat(SmsText.MAX_BODY), it.toLong(), false) }
        val array = SmsPayload.fit(rows, budget = 200_000)
        val size = array.toString().toByteArray().size
        assertTrue("tamanho $size", size <= 200_000)
        assertTrue(array.length() in 1 until 500)
    }

    @Test fun anEmptyPageIsAnEmptyArray() = assertEquals(0, SmsPayload.fit(emptyList(), budget = 1000).length())

    @Test fun entryJsonHasTheWireFields() {
        val json: JSONObject = SmsEntryJson("7", "3", "+5511999990000", "oi", 1234L, true).toJson()
        assertEquals("7", json.getString("id"))
        assertEquals("3", json.getString("threadId"))
        assertEquals("+5511999990000", json.getString("address"))
        assertEquals("oi", json.getString("body"))
        assertEquals(1234L, json.getLong("date"))
        assertTrue(json.getBoolean("outgoing"))
        assertEquals(JSONArray().length(), 0)
    }
}
