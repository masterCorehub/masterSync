package com.nexus.mastersync.services

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.nexus.mastersync.protocol.Wire
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.roundToInt

class ScanLibrary(private val context: Context) {
    data class Document(val id: String, val date: Long, val pdf: File, val pages: List<File>)
    private val root = File(context.filesDir, "scans")

    suspend fun list() = withContext(Dispatchers.IO) {
        root.listFiles().orEmpty().filter { Wire.validID(it.name) }.mapNotNull(::document)
            .sortedByDescending { it.date }
    }

    suspend fun save(pdf: Uri?, pages: List<Uri>): Document = withContext(Dispatchers.IO) {
        if (pdf == null && pages.isEmpty()) throw IOException("O scanner não entregou nenhuma página.")
        root.mkdirs()
        val id = Wire.id()
        val work = File(root, ".$id").apply { mkdirs() }
        try {
            val images = pages.mapIndexed { index, page ->
                File(work, "pagina-%02d.jpg".format(index + 1)).also { copy(page, it) }
            }
            val documentFile = File(work, "documento.pdf")
            if (pdf == null) writePdf(images, documentFile) else copy(pdf, documentFile)
            val finished = File(root, id)
            if (!work.renameTo(finished)) throw IOException("O scanner não conseguiu salvar o documento.")
            document(finished) ?: throw IOException("O documento está incompleto.")
        } finally { work.deleteRecursively() }
    }

    private fun writePdf(images: List<File>, destination: File) {
        val pdf = PdfDocument()
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)
        try {
            images.forEachIndexed { index, file ->
                val bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    // Keep the original JPEG and bound memory for the PDF copy.
                    val (width, height) = info.size.let { it.width to it.height }
                    val scale = minOf(1f, 2000f / maxOf(width, height))
                    decoder.setTargetSize((width * scale).roundToInt().coerceAtLeast(1),
                        (height * scale).roundToInt().coerceAtLeast(1))
                }
                try {
                    val landscape = bitmap.width > bitmap.height
                    val width = if (landscape) 842 else 595
                    val height = if (landscape) 595 else 842
                    val factor = minOf((width - 24f) / bitmap.width, (height - 24f) / bitmap.height)
                    val left = (width - bitmap.width * factor) / 2
                    val top = (height - bitmap.height * factor) / 2
                    val bounds = RectF(left, top, width - left, height - top)
                    val page = pdf.startPage(PdfDocument.PageInfo.Builder(width, height, index + 1).create())
                    try { page.canvas.drawBitmap(bitmap, null, bounds, paint) }
                    finally { pdf.finishPage(page) }
                } finally { bitmap.recycle() }
            }
            destination.outputStream().use(pdf::writeTo)
        } finally { pdf.close() }
    }

    suspend fun export(file: File, destination: Uri, png: Boolean = false) = withContext(Dispatchers.IO) {
        context.contentResolver.openOutputStream(destination, "wt")?.use { output ->
            if (!png) file.inputStream().use { it.copyTo(output) }
            else {
                val bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, _, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                }
                try {
                    if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)) throw IOException("Falha ao exportar PNG.")
                } finally { bitmap.recycle() }
            }
        } ?: throw IOException("O Android não conseguiu abrir o destino.")
    }

    suspend fun recognize(document: Document): String {
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            return document.pages.map { page ->
                val image = withContext(Dispatchers.IO) { InputImage.fromFilePath(context, Uri.fromFile(page)) }
                suspendCancellableCoroutine { continuation ->
                    recognizer.process(image)
                        .addOnSuccessListener { if (continuation.isActive) continuation.resume(it.text) }
                        .addOnFailureListener { if (continuation.isActive) continuation.resumeWithException(it) }
                }
            }.filter { it.isNotBlank() }.joinToString("\n\n")
        } finally { recognizer.close() }
    }

    fun name(document: Document, page: Int? = null): String {
        val stamp = java.text.SimpleDateFormat("yyyy-MM-dd HH-mm", java.util.Locale.ROOT).format(document.date)
        return if (page == null) "Digitalização $stamp.pdf" else "Digitalização $stamp - Página $page.jpg"
    }

    private fun document(folder: File): Document? {
        val pdf = File(folder, "documento.pdf")
        if (!pdf.isFile) return null
        val pages = folder.listFiles { file -> file.extension == "jpg" }.orEmpty().sortedBy { it.name }
        return Document(folder.name, pdf.lastModified(), pdf, pages)
    }

    private fun copy(uri: Uri, target: File) {
        val input = context.contentResolver.openInputStream(uri) ?: throw IOException("Não foi possível abrir uma página.")
        input.use { source -> target.outputStream().use { source.copyTo(it) } }
        if (target.length() == 0L) throw IOException("O scanner retornou um arquivo vazio. Tire a foto novamente.")
    }
}
