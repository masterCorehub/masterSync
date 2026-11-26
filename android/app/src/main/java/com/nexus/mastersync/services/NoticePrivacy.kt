package com.nexus.mastersync.services

/** Decides whether a mirrored notification hides its title and text on the Mac. */
object NoticePrivacy {
    private const val VISIBILITY_SECRET = -1 // Notification.VISIBILITY_SECRET
    private const val VISIBILITY_PUBLIC = 1 // Notification.VISIBILITY_PUBLIC

    /**
     * Content is hidden when the user asked for it, when the app marked it secret, or when the phone is
     * locked and Android's own lock screen would hide it too.
     */
    fun redact(hideAll: Boolean, visibility: Int, locked: Boolean, lockscreenAllowsPrivate: Boolean,
               lockscreenShowsNotifications: Boolean): Boolean =
        hideAll || visibility == VISIBILITY_SECRET ||
            (locked && (!lockscreenShowsNotifications || (!lockscreenAllowsPrivate && visibility != VISIBILITY_PUBLIC)))
}
