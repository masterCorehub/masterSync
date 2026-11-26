package com.nexus.mastersync.services

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NoticePrivacyTest {
    @Test fun unlockedShowsContent() =
        assertFalse(NoticePrivacy.redact(false, 0, locked = false, lockscreenAllowsPrivate = false, lockscreenShowsNotifications = true))

    @Test fun hideAllAlwaysRedacts() =
        assertTrue(NoticePrivacy.redact(true, 1, locked = false, lockscreenAllowsPrivate = true, lockscreenShowsNotifications = true))

    @Test fun secretAlwaysRedacts() =
        assertTrue(NoticePrivacy.redact(false, -1, locked = false, lockscreenAllowsPrivate = true, lockscreenShowsNotifications = true))

    @Test fun lockedShowsWhenLockscreenShowsSensitive() =
        assertFalse(NoticePrivacy.redact(false, 0, locked = true, lockscreenAllowsPrivate = true, lockscreenShowsNotifications = true))

    @Test fun lockedPrivateHiddenWhenLockscreenHidesSensitive() {
        assertTrue(NoticePrivacy.redact(false, 0, locked = true, lockscreenAllowsPrivate = false, lockscreenShowsNotifications = true))
        assertFalse(NoticePrivacy.redact(false, 1, locked = true, lockscreenAllowsPrivate = false, lockscreenShowsNotifications = true))
    }

    @Test fun lockedHiddenWhenLockscreenShowsNoNotifications() =
        assertTrue(NoticePrivacy.redact(false, 1, locked = true, lockscreenAllowsPrivate = true,
            lockscreenShowsNotifications = false))

    @Test fun unlockedIgnoresLockscreenSettings() =
        assertFalse(NoticePrivacy.redact(false, 0, locked = false, lockscreenAllowsPrivate = false,
            lockscreenShowsNotifications = false))
}
