package com.nexus.mastersync.services

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NoticePrivacyTest {
    @Test fun unlockedShowsContent() =
        assertFalse(NoticePrivacy.redact(false, 0, locked = false, lockscreenAllowsPrivate = false))

    @Test fun hideAllAlwaysRedacts() =
        assertTrue(NoticePrivacy.redact(true, 1, locked = false, lockscreenAllowsPrivate = true))

    @Test fun secretAlwaysRedacts() =
        assertTrue(NoticePrivacy.redact(false, -1, locked = false, lockscreenAllowsPrivate = true))

    @Test fun lockedShowsWhenLockscreenShowsSensitive() =
        assertFalse(NoticePrivacy.redact(false, 0, locked = true, lockscreenAllowsPrivate = true))

    @Test fun lockedPrivateHiddenWhenLockscreenHidesSensitive() {
        assertTrue(NoticePrivacy.redact(false, 0, locked = true, lockscreenAllowsPrivate = false))
        assertFalse(NoticePrivacy.redact(false, 1, locked = true, lockscreenAllowsPrivate = false))
    }
}
