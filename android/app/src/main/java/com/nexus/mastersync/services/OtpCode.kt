package com.nexus.mastersync.services

import java.text.Normalizer

/** Finds a verification code in a notification's text. The Mac uses the same rule. */
object OtpCode {
    private val keyword = Regex("codigo|code|verifica|senha|password|\\bpin\\b|token|otp|autentica|confirma|login|acesso|seguranca")
    private val candidate = Regex("(?<![\\d.,])(\\d{4,8}|\\d{3,4}[ -]\\d{3,4})(?!\\d|%|[.,]\\d)")

    private fun folded(text: String) =
        Normalizer.normalize(text, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase()

    /** The digits of the code, or null when there is no verification word or no plausible number. */
    fun find(text: String): String? {
        if (text.isEmpty()) return null
        val source = folded(text)
        val first = keyword.find(source) ?: return null
        val matches = candidate.findAll(source).filter { !source.substring(0, it.range.first).trimEnd().endsWith("$") }.toList()
        val pick = matches.firstOrNull { it.range.first >= first.range.first } ?: matches.firstOrNull()
        return pick?.value?.filter { it.isDigit() }
    }
}
