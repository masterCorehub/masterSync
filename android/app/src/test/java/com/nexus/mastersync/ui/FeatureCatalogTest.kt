package com.nexus.mastersync.ui

import com.nexus.mastersync.NexusController.Options
import com.nexus.mastersync.NexusController.Permissions
import com.nexus.mastersync.ui.features.Feature
import com.nexus.mastersync.ui.features.FeatureId
import com.nexus.mastersync.ui.features.FeatureStatus
import com.nexus.mastersync.ui.features.StepAction
import com.nexus.mastersync.ui.features.StepState
import com.nexus.mastersync.ui.features.SystemAccess
import com.nexus.mastersync.ui.features.buildFeatures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FeatureCatalogTest {
    private val allOn = Options(clipboard = true, files = true, notificationMirror = true, remoteScan = true,
        autoScan = true, gallery = true, syncNewMedia = true, mirror = true, findPhone = true, mediaControl = true, sms = true)
    private val perms = Permissions(clipboard = true, files = true, notifications = true, gallery = true,
        clipboardImages = true, chat = true, sms = true)
    private val access = SystemAccess(camera = true, mediaFull = true, mediaPartial = true,
        appNotifications = true, notificationListener = true, sms = true)

    private fun feature(id: FeatureId, options: Options, connected: Boolean = true, background: Boolean = true,
                        perms: Permissions = this.perms, access: SystemAccess = this.access): Feature =
        buildFeatures(options, perms, connected, background, access, notificationRelay = true).single { it.id == id }

    @Test fun directEditionHasNoNotificationsFeature() =
        assertTrue(buildFeatures(allOn, perms, true, true, access, notificationRelay = false)
            .none { it.id == FeatureId.Notifications })

    @Test fun fullEditionListsAllEightFeatures() =
        assertEquals(8, buildFeatures(allOn, perms, true, true, access, notificationRelay = true).size)

    @Test fun directEditionHasNoSmsFeature() =
        assertTrue(buildFeatures(allOn, perms, true, true, access, notificationRelay = false).none { it.id == FeatureId.Sms })

    @Test fun smsFirstPendingIsThePermission() {
        val s = feature(FeatureId.Sms, allOn, access = access.copy(sms = false)).status as FeatureStatus.Pending
        assertEquals(StepAction.RequestSms, s.requirement.action)
        assertEquals("Permitir SMS", s.requirement.chip)
    }

    @Test fun smsNeedsTheMacSideSwitchToo() {
        val s = feature(FeatureId.Sms, allOn, perms = perms.copy(sms = false)).status as FeatureStatus.Pending
        assertEquals("Ligar no Mac", s.requirement.chip)
        assertEquals("No Mac: SMS", s.requirement.hint)
    }

    @Test fun smsIsOffUntilTheUserTurnsItOn() =
        assertEquals(FeatureStatus.Off, feature(FeatureId.Sms, allOn.copy(sms = false)).status)

    @Test fun everythingGrantedIsActive() =
        assertTrue(buildFeatures(allOn, perms, true, true, access, true).all { it.status == FeatureStatus.Active })

    @Test fun switchedOffFeatureIsOff() =
        assertEquals(FeatureStatus.Off, feature(FeatureId.Files, allOn.copy(files = false)).status)

    @Test fun macOfflineIsAwaitingNotPending() {
        val f = feature(FeatureId.Files, allOn, connected = false, perms = Permissions())
        assertEquals(StepState.AwaitingMac, f.requirements.single().state)
        assertEquals(FeatureStatus.Active, f.status)
    }

    @Test fun macConnectedButDisabledIsPendingWithoutAction() {
        val s = feature(FeatureId.Clipboard, allOn, perms = perms.copy(clipboard = false)).status as FeatureStatus.Pending
        assertEquals("Ligar no Mac", s.requirement.chip)
        assertNull(s.requirement.action)
        assertEquals("No Mac: Celular → Área de transferência", s.requirement.hint)
    }

    @Test fun galleryFirstPendingIsMediaPermission() {
        val s = feature(FeatureId.Gallery, allOn, access = access.copy(mediaFull = false, mediaPartial = false)).status
        assertEquals(StepAction.RequestGallery, (s as FeatureStatus.Pending).requirement.action)
        assertEquals("Permitir fotos", s.requirement.chip)
    }

    @Test fun partialMediaCountsAsGranted() =
        assertEquals(FeatureStatus.Active,
            feature(FeatureId.Gallery, allOn, access = access.copy(mediaFull = false, mediaPartial = true)).status)

    @Test fun optionalBackgroundDoesNotMakeClipboardPending() =
        assertEquals(FeatureStatus.Active, feature(FeatureId.Clipboard, allOn, background = false).status)

    @Test fun mirrorRequiresBackground() =
        assertEquals(StepAction.ToggleBackground,
            (feature(FeatureId.Mirror, allOn, background = false).status as FeatureStatus.Pending).requirement.action)

    @Test fun scanMainSwitchIsRemoteScan() {
        assertEquals(FeatureStatus.Off, feature(FeatureId.Scan, allOn.copy(remoteScan = false)).status)
        assertNotEquals(FeatureStatus.Off, feature(FeatureId.Scan, allOn.copy(autoScan = false)).status)
    }

    @Test fun scanWithFilesOffOnAndroidOffersToEnableFiles() =
        assertEquals(StepAction.EnableFiles,
            (feature(FeatureId.Scan, allOn.copy(files = false)).status as FeatureStatus.Pending).requirement.action)

    @Test fun notificationsNeedListenerAccessFirst() {
        val s = feature(FeatureId.Notifications, allOn, access = access.copy(notificationListener = false)).status
        assertEquals(StepAction.OpenNotificationAccess, (s as FeatureStatus.Pending).requirement.action)
    }
}
