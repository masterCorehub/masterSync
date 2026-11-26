# Imagens na Conversa, links e remetente: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Conversa dos dois apps mostra imagens como imagens, links clicáveis no Android e o dispositivo que enviou cada item.

**Architecture:** Lógica pura e testada em arquivos novos (`ChatMedia`) de cada lado; as telas só a usam. Nenhuma mudança de protocolo.

**Tech Stack:** Kotlin / Compose (Android), Swift / SwiftUI + ImageIO (Mac).

**Spec:** `docs/superpowers/specs/2026-11-26-chat-media-and-sender-design.md`

## Global Constraints

- Mimes com prévia (iguais nos dois lados): `image/jpeg`, `image/png`, `image/webp`, `image/gif`, `image/heic`, `image/heif`. No Android, só até 50 MB (`50 * 1024 * 1024`).
- Alvo de decodificação no Android: maior lado perto de 1080 px. Miniatura no Mac: maior lado 280 pt (560 px).
- Decodificação sempre fora da thread principal. Falha cai no cartão de hoje.
- O arquivo original nunca é alterado. "Salvar" e "Abrir prévia" usam o original.
- Textos em português do Brasil. Fallbacks de nome: "Este celular" / "Este Mac" (próprio) e "Mac" / "Celular" (outro).
- Verificação Android: `.superpowers/g :app:testFullDebugUnitTest :app:testDirectDebugUnitTest :app:assembleFullDebug :app:assembleDirectDebug`. Verificação Mac: `.superpowers/m`.

## Review Focus

1. Imagem com dimensões enormes (por exemplo 12000×9000) usa um `sampleSize` que mantém a decodificação reduzida. Teste `ChatMediaTest.hugeImageIsDownsampled`.
2. URL no meio de uma frase, com pontuação final e com parênteses, vira link sem a pontuação. Teste `ChatMediaTest.linkKeepsTrailingPunctuationOutside`.
3. Arquivo cujo mime diz imagem mas cujos bytes não decodificam cai no cartão, sem travar (Mac: `testThumbnailOfNonImageIsNil`).
4. Nome do dispositivo vazio ou só com espaços usa o fallback. Teste `ChatMediaTest.blankNamesFallBack`.
5. Item de histórico antigo, sem horário, mostra só o nome (Android: `ChatMediaTest.captionOmitsMissingTime`).

---

### Task 1: Android — lógica pura de mídia, links e remetente

**Files:**
- Create: `android/app/src/main/java/com/nexus/mastersync/ui/conversation/ChatMedia.kt`
- Test: `android/app/src/test/java/com/nexus/mastersync/ui/ChatMediaTest.kt`

**Interfaces:**
- Produces:

```kotlin
object ChatMedia {
    const val MAX_PREVIEW_BYTES = 50L * 1024 * 1024
    const val TARGET_EDGE = 1080
    fun isPreviewableImage(mime: String, size: Long): Boolean
    fun sampleSize(width: Int, height: Int, targetEdge: Int = TARGET_EDGE): Int   // potência de 2 >= 1
    data class Span(val text: String, val url: String?)
    fun linkSpans(text: String): List<Span>
    fun senderName(outgoing: Boolean, localName: String, peerName: String): String
    fun caption(name: String, time: Long, format: (Long) -> String): String      // "Nome · 14:32" ou "Nome"
}
```

Regras:
- `isPreviewableImage`: compara o mime em minúsculas com a lista da seção Global Constraints e exige `size in 1..MAX_PREVIEW_BYTES`.
- `sampleSize`: a maior potência de 2 tal que `max(w, h) / sample >= targetEdge`, no mínimo 1.
- `linkSpans`: divide em trechos de texto e de link (`https?://` até um espaço). Tira do fim do link `.,;:!?` e um `)` sem `(` correspondente, devolvendo essa pontuação como texto. Sem link, devolve um único `Span(text, null)`.
- `senderName`: `outgoing` usa `localName`, senão `peerName`. Vazio ou só espaços usa "Este celular" (próprio) ou "Mac" (outro).
- `caption`: `"$name · ${format(time)}"` quando `time > 0`, senão `name`.

- [ ] **Step 1: Write the failing tests** em `ChatMediaTest`:

```kotlin
@Test fun previewableImageRules()      // image/png 1 KB true; IMAGE/JPEG maiúsculo true; application/pdf false; image/png 0 false; image/png 51 MB false
@Test fun hugeImageIsDownsampled()     // sampleSize(12000, 9000) == 8; sampleSize(800, 600) == 1; sampleSize(2200, 1000) == 2
@Test fun linkSpansSplitText()         // "veja https://a.com/x ok" → [Span("veja ", null), Span("https://a.com/x", "https://a.com/x"), Span(" ok", null)]
@Test fun linkKeepsTrailingPunctuationOutside() // "(https://a.com/x)." → link "https://a.com/x"; ")." fica como texto
@Test fun textWithoutLinkIsOneSpan()
@Test fun blankNamesFallBack()         // senderName(true, "  ", "Mac Air") == "Este celular"; senderName(false, "S23", "") == "Mac"; senderName(true, "S23", "x") == "S23"
@Test fun captionOmitsMissingTime()    // caption("S23", 0, ...) == "S23"; caption("S23", 5, { "14:32" }) == "S23 · 14:32"
```

- [ ] **Step 2: Run** `.superpowers/g :app:testFullDebugUnitTest --tests '*ChatMediaTest'`. Expected: FAIL (símbolos inexistentes).
- [ ] **Step 3: Implement** `ChatMedia` conforme as regras.
- [ ] **Step 4: Run** o mesmo comando. Expected: PASS. Commit `feat(android): lógica de mídia, links e remetente da Conversa`.

---

### Task 2: Android — imagens, links e remetente na Conversa

**Files:**
- Modify: `android/app/src/main/java/com/nexus/mastersync/ui/conversation/ConversationScreen.kt`

**Interfaces:**
- Consumes: `ChatMedia` (Task 1), `TimelineItem` (já existe).

- [ ] **Step 1: Implement** (verificação por build e pelo aparelho, porque não há testes de UI no projeto):
  - `localName = Build.MODEL` e `peerName = status.connected?.name.orEmpty()`.
  - `Bubble` e `FileCard`: uma linha de legenda acima do conteúdo, com `ChatMedia.caption(ChatMedia.senderName(entry.outgoing, localName, peerName), time, ::formatTime)`. O tempo vem de `entry.time` para mensagens, `sent.time` para enviados e `time` para recebidos. Texto pequeno (`labelSmall`) na cor `muted`.
  - `Bubble`: `ChatMedia.linkSpans` vira `AnnotatedString`, usando `withLink(LinkAnnotation.Url(url))` e a cor `accent` com sublinhado nos links.
  - Novo `ImageBubble(received: Received, caption: String, onSave: () -> Unit)` para `ReceivedFile` com `isPreviewableImage(item.mime, item.size)`:
    - `produceState` em `Dispatchers.IO`: lê as dimensões com `inJustDecodeBounds`, decodifica com `inSampleSize = ChatMedia.sampleSize(w, h)` e captura qualquer `Throwable` (inclusive `OutOfMemoryError`), devolvendo `null`;
    - enquanto carrega mostra uma caixa `control` de 200×140 dp;
    - com bitmap: `Image` com `ContentScale.Fit`, máximo 280 dp de largura e cantos de 14 dp, com o botão "Salvar" embaixo;
    - com `null`: cai no `FileCard`.
- [ ] **Step 2: Run** a verificação completa do Android. Expected: PASS. Commit `feat(android): imagens, links clicáveis e remetente na Conversa`.

---

### Task 3: Mac — miniaturas e remetente na Conversa

**Files:**
- Create: `macOS/Sources/NexusMasterSync/ChatMedia.swift`
- Modify: `macOS/Sources/NexusMasterSync/Dashboard.swift` (`conversationBubble`, ~738-759)
- Test: `macOS/Tests/NexusCoreTests/ChatMediaTests.swift`

**Interfaces:**
- Produces:

```swift
enum ChatMedia {
    nonisolated static let previewMimes: Set<String>
    nonisolated static func isImage(mime: String) -> Bool
    nonisolated static func senderName(outgoing: Bool, local: String, peer: String) -> String   // fallbacks "Este Mac" / "Celular"
    nonisolated static func thumbnail(url: URL, maxPixel: Int) -> NSImage?                      // ImageIO, nil se não for imagem
}
```

- [ ] **Step 1: Write the failing tests:**

```swift
func testIsImageUsesTheSharedMimeList()      // image/png, IMAGE/JPEG, image/heic true; application/pdf, text/plain false
func testBlankNamesFallBack()                // senderName(outgoing: true, local: " ", peer: "S23") == "Este Mac"; (false, "Air", "") == "Celular"
func testThumbnailKeepsAspectAndLimitsSize() // PNG 200×100 em /tmp, maxPixel 64 → maior lado 64, razão 2:1 (±1)
func testThumbnailOfNonImageIsNil()          // arquivo de texto com extensão .png → nil
```

- [ ] **Step 2: Run** `.superpowers/m --filter ChatMediaTests`. Expected: falha de compilação.
- [ ] **Step 3: Implement** `ChatMedia` (miniatura com `CGImageSourceCreateWithURL` e `CGImageSourceCreateThumbnailAtIndex`, com `kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceCreateThumbnailWithTransform` e `kCGImageSourceThumbnailMaxPixelSize`).
- [ ] **Step 4: UI.** Em `conversationBubble`:
  - acima do conteúdo, uma legenda `caption` (`font(.caption2)`, `muted`) com o nome (`ChatMedia.senderName(outgoing:local: Host.current().localizedName ?? "", peer: model.selected?.name ?? "")`) e `· hora` quando houver;
  - para `.file` com `ChatMedia.isImage(mime: item.offer.mime)`, mostra a miniatura (carregada em `Task.detached` e guardada num `NSCache` por caminho), com `frame(maxWidth: 280)`, cantos de 10 e clique que abre `preview = item.url`;
  - sem miniatura (ainda carregando ou falhou), mostra o `Label` de hoje.
- [ ] **Step 5: Run** `.superpowers/m`. Expected: PASS. Commit `feat(mac): miniaturas e remetente na Conversa`.

---

### Task 4: Verificação no aparelho

- [ ] Gerar os dois apps e instalar o APK por Wi-Fi.
- [ ] No Finder, enviar uma foto com Serviços → Enviar ao Android: ela aparece como imagem na Conversa do Android e como miniatura na do Mac, com o nome de cada aparelho.
- [ ] Enviar um PDF: aparece como cartão. Enviar um texto com um link: o link abre no navegador.
