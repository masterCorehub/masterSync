package com.nexus.mastersync

import android.Manifest
import android.app.NotificationManager
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.mutableStateOf
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import com.nexus.mastersync.services.ConnectionService
import com.nexus.mastersync.services.ScanLibrary
import com.nexus.mastersync.services.ScreenMirrorService
import com.nexus.mastersync.protocol.Wire
import com.nexus.mastersync.ui.NexusActions
import com.nexus.mastersync.ui.NexusScreen
import com.nexus.mastersync.ui.features.FeatureId
import com.nexus.mastersync.ui.Tab
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.io.File

class MainActivity : ComponentActivity() {
    private val nexus get() = (application as NexusApplication).nexus
    private val library get() = nexus.scans
    private val tab = mutableStateOf(Tab.Home)
    private val openFeature = mutableStateOf<FeatureId?>(null)
    private val shared = mutableStateOf<Uri?>(null)
    private val documents = mutableStateOf<List<ScanLibrary.Document>>(emptyList())
    private val busy = mutableStateOf(false)
    private val recognized = mutableStateOf<String?>(null)
    private var scanPeer: String? = null
    private var scanRequestID: String? = null
    private var captureId: String? = null
    private var photoCapture: NexusController.CameraRequest? = null
    private var advancedScanPending = false
    private var screenRequest: NexusController.MirrorRequest? = null
    private var exportTask: Pair<File, Boolean>? = null


    private val qr = registerForActivityResult(ScanContract()) { result ->
        result.contents?.let { nexus.client.pair(it) }
    }
    private val camera = registerForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
        if (allowed) launchQr() else nexus.note("Permita a câmera para ler o QR.")
    }
    private val notifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        startConnection()
    }
    private val screenNotifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
        if (allowed) approveScreen() else {
            nexus.decideMirror(false)
            nexus.note("Permita notificações para ver o indicador de espelhamento.")
        }
    }
    private val screenConsent = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val request = screenRequest
        screenRequest = null
        val data = result.data
        if (request == null) return@registerForActivityResult
        val allowed = nexus.confirmMirror(request, result.resultCode == RESULT_OK && data != null)
        if (!allowed || data == null) {
            nexus.client.sendTo(request.peer, Wire.message("screenEnded").put("message", "Captura não autorizada."))
            return@registerForActivityResult
        }
        runCatching {
            startForegroundService(Intent(this, ScreenMirrorService::class.java)
                .putExtra("peer", request.peer).putExtra("size", request.size).putExtra("fps", request.fps)
                .putExtra("quality", request.quality).putExtra("consent", data))
        }.onFailure {
            nexus.setMirroring(false)
            nexus.note("O Android não permitiu iniciar o espelhamento.")
        }
    }
    private val galleryAccess = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        val permitted = nexus.gallery.available()
        nexus.update(nexus.options.value.copy(gallery = permitted))
        if (!permitted) nexus.note("Selecione as fotos e os vídeos que o Mac pode ver.")
    }
    private val chooseFile = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { nexus.offerFile(it) }
    }
    private val createFile = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val job = exportTask
        exportTask = null
        val uri = result.data?.data
        if (result.resultCode != RESULT_OK || uri == null || job == null) return@registerForActivityResult
        lifecycleScope.launch {
            runCatching { library.export(job.first, uri, job.second) }
                .onSuccess { nexus.note("Arquivo salvo.") }
                .onFailure { nexus.note(it.message ?: "Falha ao salvar o arquivo.") }
        }
    }

    private val instantCamera = registerForActivityResult(object : ActivityResultContracts.TakePicture() {
        override fun createIntent(context: Context, input: Uri): Intent = super.createIntent(context, input).apply {
            clipData = ClipData.newRawUri("Foto instantânea", input)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
    }) { taken ->
        val request = photoCapture ?: return@registerForActivityResult
        val file = captureFile(request.id)
        photoCapture = null
        if (!taken || !file.isFile || file.length() == 0L) {
            file.delete()
            nexus.photoStatus(request, "Foto cancelada no Android.")
            nexus.finishPhoto(request)
        } else if (nexus.client.status.value.connected?.id != request.peer ||
            !nexus.options.value.files || !nexus.permissions.value.files) {
            file.delete()
            nexus.photoStatus(request, "O Mac não está disponível para receber a foto.")
            nexus.finishPhoto(request)
        } else {
            nexus.photoStatus(request, "Enviando foto…", finished = false)
            val name = "Foto instantânea ${java.text.SimpleDateFormat("yyyy-MM-dd HH-mm-ss", java.util.Locale.ROOT).format(java.util.Date())}.jpg"
            nexus.transfers.offerFile(file, request.peer, name, "image/jpeg", transferId = request.id) {
                nexus.photoStatus(request, it)
            }.invokeOnCompletion { file.delete() }
            nexus.finishPhoto(request)
        }
    }
    private val instantCameraPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
        if (allowed) launchInstantCamera() else failInstantCamera("Permita o uso da câmera para tirar a foto.")
    }

    private fun approveInstantCamera() {
        if (busy.value || photoCapture != null) return
        photoCapture = nexus.decidePhoto(true) ?: return
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) launchInstantCamera()
        else instantCameraPermission.launch(Manifest.permission.CAMERA)
    }

    private fun launchInstantCamera() {
        val request = photoCapture ?: return
        runCatching {
            val file = captureFile(request.id)
            file.parentFile?.mkdirs()
            check(file.createNewFile())
            instantCamera.launch(FileProvider.getUriForFile(this, "$packageName.scan-capture", file))
        }.onFailure { failInstantCamera("Não foi possível abrir a câmera do Android.") }
    }

    private fun failInstantCamera(message: String) {
        val request = photoCapture ?: return
        captureFile(request.id).delete()
        photoCapture = null
        nexus.photoStatus(request, message)
        nexus.finishPhoto(request)
    }

    private val documentCamera = registerForActivityResult(object : ActivityResultContracts.TakePicture() {
        override fun createIntent(context: Context, input: Uri): Intent = super.createIntent(context, input).apply {
            // Grant the camera only the URI of the temporary photo it writes.
            clipData = ClipData.newRawUri("Página digitalizada", input)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
    }) { taken ->
        val file = captureId?.let(::captureFile)
        if (!taken || file == null || !file.isFile) {
            failScan("A câmera foi fechada sem uma foto confirmada. Tente fotografar o documento novamente.")
        } else {
            captureId = null
            finishScan(null, listOf(Uri.fromFile(file)), file)
        }
    }
    private val documentCameraPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
        if (allowed) launchDocumentCamera() else failScan("Permita o uso da câmera para fotografar o documento.")
    }

    private val scannerResult = registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        val scan = if (result.resultCode == RESULT_OK) runCatching {
            GmsDocumentScanningResult.fromActivityResultIntent(result.data)
        }.getOrNull() else null
        val pdf = scan?.pdf?.uri
        val pages = scan?.pages.orEmpty().map { it.imageUri }
        if (pdf == null && pages.isEmpty()) {
            failScan("O scanner avançado não entregou nenhuma página. Use Fotografar documento para tentar pela câmera.")
        } else finishScan(pdf, pages)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        savedInstanceState?.getString("screen-peer")?.let {
            screenRequest = NexusController.MirrorRequest(it, savedInstanceState.getString("screen-id").orEmpty(), savedInstanceState.getInt("screen-size"),
                savedInstanceState.getInt("screen-fps"), savedInstanceState.getInt("screen-quality"))
        }
        savedInstanceState?.getString("photo-peer")?.let { peer ->
            savedInstanceState.getString("photo-id")?.takeIf(Wire::validID)?.let {
                photoCapture = NexusController.CameraRequest(peer, it)
            }
        }
        scanPeer = savedInstanceState?.getString("scan-peer")
        scanRequestID = savedInstanceState?.getString("scan-request-id")?.takeIf(Wire::validID)
        captureId = savedInstanceState?.getString("scan-capture")?.takeIf(Wire::validID)
        advancedScanPending = savedInstanceState?.getBoolean("scan-advanced") == true
        busy.value = captureId != null || advancedScanPending
        tab.value = Tab.restore(savedInstanceState?.getString("tab"))
        savedInstanceState?.getString("export-file")?.let { exportTask = File(it) to savedInstanceState.getBoolean("export-png") }
        handle(intent)
        lifecycleScope.launch { documents.value = library.list() }
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                nexus.client.status.collect { status ->
                    if (status.connected != null) startConnection()
                }
            }
        }
        setContent {
            NexusScreen(
                nexus = nexus, actions = actions, tab = tab.value, navigate = { tab.value = it },
                openFeature = openFeature.value, setOpenFeature = { openFeature.value = it },
                shared = shared.value, clearShared = { shared.value = null },
                documents = documents.value, scannerBusy = busy.value, recognized = recognized.value
            )
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        photoCapture?.let {
            outState.putString("photo-peer", it.peer)
            outState.putString("photo-id", it.id)
        }
        outState.putString("scan-peer", scanPeer)
        outState.putString("scan-request-id", scanRequestID)
        outState.putString("scan-capture", captureId)
        outState.putBoolean("scan-advanced", advancedScanPending)
        screenRequest?.let {
            outState.putString("screen-peer", it.peer)
            outState.putString("screen-id", it.id)
            outState.putInt("screen-size", it.size)
            outState.putInt("screen-fps", it.fps)
            outState.putInt("screen-quality", it.quality)
        }
        outState.putString("tab", tab.value.name)
        exportTask?.let {
            outState.putString("export-file", it.first.path)
            outState.putBoolean("export-png", it.second)
        }
        super.onSaveInstanceState(outState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    override fun onStart() {
        super.onStart()
        nexus.setVisible(true)
        if (nexus.client.selectedAuthorizedMac() != null) startConnection()
    }
    override fun onResume() { super.onResume(); nexus.refreshPermissions() }
    override fun onStop() { nexus.setVisible(false); super.onStop() }
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        nexus.setFocus(hasFocus)
    }

    @Suppress("DEPRECATION")
    private fun handle(intent: Intent) {
        if (intent.action == Intent.ACTION_SEND) {
            val stream: Uri? = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else intent.getParcelableExtra(Intent.EXTRA_STREAM)
            shared.value = stream?.takeIf { it.scheme == "content" }
            tab.value = Tab.Conversation
        } else if (intent.getBooleanExtra("open-share", false)) tab.value = Tab.Conversation
        else if (intent.getBooleanExtra("open-scan", false)) {
            tab.value = Tab.Home
            openFeature.value = FeatureId.Scan
        }
    }

    private val actions by lazy {
        NexusActions(
            readQr = ::readQr, chooseFile = { chooseFile.launch(arrayOf("*/*")) },
            toggleBackground = ::toggleConnection, openNotificationAccess = ::notificationAccess,
            openDndAccess = { startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)) },
            openAppSettings = {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
            },
            requestGallery = ::requestGallery, approvePhoto = ::approveInstantCamera, approveScreen = ::requestScreen,
            keyboardSettings = { startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)) },
            chooseKeyboard = { getSystemService(InputMethodManager::class.java).showInputMethodPicker() },
            scan = { openDocumentCamera() }, advancedScan = { openScanner() },
            acceptScan = { advanced ->
                nexus.decideScan(true)?.let { request ->
                    if (advanced) openScanner(request.peer, request.id)
                    else openDocumentCamera(request.peer, request.id)
                }
            },
            ocr = ::recognize, dismissOcr = { recognized.value = null },
            sendDocument = { document -> nexus.client.status.value.connected?.id?.let { sendDocument(document, it) } },
            export = ::export
        )
    }

    private fun readQr() {
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            camera.launch(Manifest.permission.CAMERA)
        } else launchQr()
    }

    private fun launchQr() = qr.launch(ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE)
        .setPrompt("Aponte para o código no Mac.").setBeepEnabled(false).setOrientationLocked(false))

    private fun toggleConnection() {
        if (nexus.background.value) {
            nexus.requestBackgroundConnection(false)
            stopService(Intent(this, ConnectionService::class.java))
            return
        }
        nexus.requestBackgroundConnection(true)
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else startConnection()
    }

    private fun startConnection() {
        if (!nexus.beginBackgroundStart()) return
        runCatching { startForegroundService(Intent(this, ConnectionService::class.java)) }
            .onFailure {
                nexus.setBackground(false)
                nexus.note("O Android não permitiu iniciar a conexão em segundo plano.")
            }
    }

    private fun requestScreen() {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            screenNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else if (nexus.canPostNotifications()) approveScreen()
        else {
            nexus.decideMirror(false)
            nexus.note("Ative notificações para ver o indicador de espelhamento.")
        }
    }

    private fun approveScreen() {
        val request = nexus.decideMirror(true) ?: return
        screenRequest = request
        val manager = getSystemService(MediaProjectionManager::class.java)
        val intent = if (Build.VERSION.SDK_INT >= 34) {
            manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
        } else manager.createScreenCaptureIntent()
        screenConsent.launch(intent)
    }

    private fun requestGallery() {
        val permissions = if (Build.VERSION.SDK_INT >= 34) {
            arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
        } else if (Build.VERSION.SDK_INT >= 33) {
            arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
        } else arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        galleryAccess.launch(permissions)
    }

    private fun notificationAccess() = startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))

    private fun openDocumentCamera(authorizedPeer: String? = null, requestID: String? = null) {
        if (busy.value) return
        openFeature.value = FeatureId.Scan
        nexus.note("")
        scanPeer = nexus.scanDestination(authorizedPeer)
        scanRequestID = requestID
        captureId = Wire.id()
        busy.value = true
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) launchDocumentCamera()
        else documentCameraPermission.launch(Manifest.permission.CAMERA)
    }

    private fun captureFile(id: String) = File(File(cacheDir, "scan-capture"), "$id.jpg")

    private fun launchDocumentCamera() {
        val id = captureId ?: return
        runCatching {
            val file = captureFile(id)
            file.parentFile?.mkdirs()
            check(file.createNewFile())
            val uri = FileProvider.getUriForFile(this, "$packageName.scan-capture", file)
            documentCamera.launch(uri)
        }.onFailure { failScan("Não foi possível abrir a câmera. Verifique se há um app de câmera disponível.") }
    }

    private fun openScanner(authorizedPeer: String? = null, requestID: String? = null) {
        if (busy.value) return
        nexus.note("")
        scanPeer = nexus.scanDestination(authorizedPeer)
        scanRequestID = requestID
        val options = GmsDocumentScannerOptions.Builder()
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .setGalleryImportAllowed(true).setPageLimit(20)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG, GmsDocumentScannerOptions.RESULT_FORMAT_PDF)
            .build()
        busy.value = true
        GmsDocumentScanning.getClient(options).getStartScanIntent(this)
            .addOnSuccessListener(this) { sender ->
                advancedScanPending = true
                runCatching { scannerResult.launch(IntentSenderRequest.Builder(sender).build()) }
                    .onFailure { failScan("O scanner avançado não abriu. Use Fotografar documento para continuar.") }
            }
            .addOnFailureListener(this) { failScan("Scanner avançado indisponível. Use Fotografar documento para continuar.") }
    }

    private fun finishScan(pdf: Uri?, pages: List<Uri>, capture: File? = null) {
        val peer = scanPeer
        val requestID = scanRequestID
        scanPeer = null
        scanRequestID = null
        advancedScanPending = false
        busy.value = true
        nexus.note("Salvando digitalização…")
        lifecycleScope.launch {
            try {
                nexus.saveScan(pdf, pages, peer, capture, requestID)
                documents.value = library.list()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                showScanIssue(error.localizedMessage ?: "Falha ao salvar a digitalização. Tente fotografar novamente.", peer, requestID)
            } finally { busy.value = false }
        }
    }

    private fun failScan(message: String) {
        captureId?.let { captureFile(it).delete() }
        captureId = null
        advancedScanPending = false
        busy.value = false
        showScanIssue(message, scanPeer, scanRequestID)
        scanPeer = null
        scanRequestID = null
    }

    private fun showScanIssue(message: String, peer: String?, requestID: String? = null) {
        nexus.note(message)
        if (peer != null) {
            val status = Wire.message("scanStatus").put("message", message.take(130))
            requestID?.let { status.put("id", it).put("more", false) }
            nexus.client.sendTo(peer, status)
        }
    }

    private fun recognize(document: ScanLibrary.Document) {
        if (busy.value) return
        lifecycleScope.launch {
            busy.value = true
            runCatching { library.recognize(document) }
                .onSuccess { recognized.value = it.ifBlank { "Nenhum texto reconhecido." } }
                .onFailure { nexus.note(it.message ?: "Falha no reconhecimento de texto.") }
            busy.value = false
        }
    }

    private fun sendDocument(document: ScanLibrary.Document, peer: String) {
        if (!nexus.options.value.files) {
            nexus.note("Ative arquivos antes de enviar a digitalização.")
            return
        }
        nexus.transfers.offerFile(document.pdf, peer, library.name(document), "application/pdf")
    }

    private fun export(file: File, mime: String, name: String, png: Boolean) {
        exportTask = file to png
        createFile.launch(Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE).setType(mime).putExtra(Intent.EXTRA_TITLE, name))
    }
}
