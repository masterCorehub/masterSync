package com.nexus.mastersync.services

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OtpCodeTest {
    @Test fun findsTypicalCodes() {
        assertEquals("482913", OtpCode.find("Seu código de verificação é 482 913. Não compartilhe."))
        assertEquals("123456", OtpCode.find("G-123456 é o seu código de verificação do Google"))
        assertEquals("4821", OtpCode.find("Código: 4821"))
        assertEquals("123456", OtpCode.find("Your verification code is 123456"))
        assertEquals("482913", OtpCode.find("Token de segurança 482-913 válido por 5 minutos"))
    }

    @Test fun ignoresTextWithoutAVerificationWord() {
        assertNull(OtpCode.find("Seu pedido 12345678 saiu para entrega"))
        assertNull(OtpCode.find("Compra de R$ 1234 aprovada em Padaria Central"))
        assertNull(OtpCode.find(""))
    }

    @Test fun ignoresNumbersThatAreNotCodes() {
        assertNull(OtpCode.find("Código de rastreio 12"))
        assertNull(OtpCode.find("Código de barras 123456789012"))
        assertNull(OtpCode.find("Senha alterada em 12:34"))
        assertNull(OtpCode.find("Código promocional: 50% de desconto"))
        assertNull(OtpCode.find("Código de confirmação enviado. Valor R$ 12345"))
    }

    @Test fun prefersTheNumberAfterTheKeyword() =
        assertEquals("4455", OtpCode.find("Pedido 99887766. Código de verificação: 4455"))
}
