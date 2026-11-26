package com.nexus.mastersync.ui

import com.nexus.mastersync.services.ScanLibrary
import java.io.File

/** Everything the screens ask the Activity to do (permissions, system screens, camera, files). */
data class NexusActions(
    val readQr: () -> Unit,
    val chooseFile: () -> Unit,
    val toggleBackground: () -> Unit,
    val openNotificationAccess: () -> Unit,
    val openDndAccess: () -> Unit,
    val openAppSettings: () -> Unit,
    val requestGallery: () -> Unit,
    val approvePhoto: () -> Unit,
    val approveScreen: () -> Unit,
    val keyboardSettings: () -> Unit,
    val chooseKeyboard: () -> Unit,
    val scan: () -> Unit,
    val advancedScan: () -> Unit,
    val acceptScan: (advanced: Boolean) -> Unit,
    val ocr: (ScanLibrary.Document) -> Unit,
    val dismissOcr: () -> Unit,
    val sendDocument: (ScanLibrary.Document) -> Unit,
    val export: (File, String, String, Boolean) -> Unit
)
