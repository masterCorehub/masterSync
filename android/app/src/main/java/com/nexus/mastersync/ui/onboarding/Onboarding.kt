package com.nexus.mastersync.ui.onboarding

/** The four pages of the first-run flow. */
enum class OnboardingPage(val title: String, val body: String) {
    Welcome("Bem-vindo ao MasterSync",
        "Seu celular e seu Mac conversando direto pela sua rede Wi‑Fi: notificações, SMS, fotos, arquivos e área de transferência. Sem conta e sem nuvem."),
    Mac("Abra o MasterSync no Mac",
        "Instale e abra o MasterSync no Mac e deixe os dois aparelhos na mesma rede Wi‑Fi. No Mac, vá em Dispositivos, toque em Ativar rede local e depois em Gerar QR."),
    Pair("Leia o QR do Mac",
        "Toque em Ler QR e aponte a câmera para o código na tela do Mac. Depois confira o nome do celular no Mac e toque em Autorizar."),
    Features("O que você quer usar?",
        "Ligue só o que precisar. Cada recurso pede as permissões dele, e você muda tudo depois na tela Início.");

    val next: OnboardingPage? get() = entries.getOrNull(ordinal + 1)
    val previous: OnboardingPage? get() = entries.getOrNull(ordinal - 1)
    val isLast: Boolean get() = next == null
    val position: String get() = "${ordinal + 1} de ${entries.size}"
}

object Onboarding {
    fun shouldShow(done: Boolean, hasPairedMac: Boolean): Boolean = !done && !hasPairedMac

    /** The pairing page only moves on once a Mac is really connected; the others are free to continue. */
    fun canContinue(page: OnboardingPage, connected: Boolean): Boolean = page != OnboardingPage.Pair || connected
}
