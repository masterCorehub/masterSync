# Cartão do player de mídia: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Um cartão de player translúcido no Mac, com capa, dados da faixa, controles, barra de progresso e a escolha de saída Celular | Mac.

**Architecture:** O Android monta o status a partir da sessão de mídia ativa com lógica pura testável (`MediaPayload`) e responde a pedidos de capa e fila. O Mac interpreta o status numa estrutura pura (`MediaPlayerState`), guarda capa e fila no modelo e desenha o cartão numa view própria.

**Tech Stack:** Kotlin (MediaSession, org.json) e Swift / SwiftUI (`ImageRenderer` nos testes de aparência).

**Spec:** `docs/superpowers/specs/2026-11-26-media-player-card-design.md`

## Global Constraints

- Acréscimos de protocolo apenas; Mac e Android antigos continuam funcionando (campos ausentes são ignorados).
- Capa: JPEG de até 256 px e 48 KB no Android; no Mac só se aceita até 64 KiB que decodifiquem como imagem (`NexusModel.acceptedIcon`). Fila: no máximo 30 itens.
- Textos em português do Brasil: "Artista", "Álbum", "Ano", "N de M", "Faixa N", "Saída", "Celular", "Mac", "Nada tocando no Android".
- Nenhuma compilação em release nem instalação no aparelho neste plano (preferência do usuário): só testes e checagem de compilação.
- Verificação Android: `.superpowers/g :app:testFullDebugUnitTest :app:testDirectDebugUnitTest :app:assembleFullDebug :app:assembleDirectDebug`. Verificação Mac: `.superpowers/m`.

## Review Focus

1. Posição além da duração, negativa ou com velocidade zero: a barra nunca sai de 0 até a duração. Testes `MediaPayloadTest.positionIsClamped` e `MediaPlayerStateTests.testPositionClampsToDuration`.
2. Duas faixas com o mesmo título e álbuns diferentes têm `artKey` diferentes, e a capa que chega com uma chave antiga é descartada. Testes `MediaPayloadTest.artKeyDiffersByAlbum` e `testStaleArtIsIgnored`.
3. Status de um Android antigo (só `name`, `text`, `playing`) mostra título e artista e nenhuma linha vazia. Teste `testLegacyMessageStillParses`.
4. Duração desconhecida (0): sem barra arrastável e sem divisão por zero. Teste `testFractionWithoutDurationIsZero`.
5. Capa inválida ou grande demais é descartada sem trocar a capa atual. Teste `testInvalidArtIsRejected`.

---

### Task 1: Android — lógica pura do status de mídia

**Files:**
- Create: `android/app/src/main/java/com/nexus/mastersync/services/MediaPayload.kt`
- Test: `android/app/src/test/java/com/nexus/mastersync/services/MediaPayloadTest.kt`

**Interfaces:**
- Produces:

```kotlin
data class MediaSnapshot(
    val title: String?, val artist: String?, val album: String?,
    val year: Int, val track: Int, val tracks: Int,
    val durationMs: Long, val positionMs: Long, val updatedAt: Long, val speed: Float, val playing: Boolean?,
    val canSeek: Boolean, val canLike: Boolean, val liked: Boolean, val hasQueue: Boolean)

object MediaPayload {
    const val MAX_QUEUE = 30
    fun artKey(title: String?, artist: String?, album: String?): String
    fun positionNow(positionMs: Long, updatedAt: Long, now: Long, speed: Float, playing: Boolean, durationMs: Long): Long
    fun status(snapshot: MediaSnapshot, now: Long): JSONObject
}
```

Regras:
- `artKey`: vazio se título, artista e álbum forem todos vazios; senão os 8 primeiros bytes do SHA-256 de `"$title\u0000$artist\u0000$album"` em hexadecimal.
- `positionNow`: se tocando, `positionMs + (now - updatedAt) * speed`; senão `positionMs`. Nunca menor que 0 e, com `durationMs > 0`, nunca maior que ela.
- `status`: `type` = `mediaStatus`. Sempre `name` (título) e `text` (artista) quando existirem, para o Mac antigo. Acrescenta `artist`, `albumName`, `year`, `trackNumber`, `trackCount` (só se > 0 ou não vazios), `durationMs` (> 0), `positionMs` (da `positionNow`), `speed`, `playing`, `artKey` (não vazio), `canSeek`, `canLike`, `liked` (só se `canLike`), `hasQueue`. Textos cortados em 150 caracteres.

- [ ] **Step 1: Write the failing tests** em `MediaPayloadTest`:

```kotlin
@Test fun artKeyIsStableAndEmptyForNoData()      // mesma entrada → mesma chave de 16 hex; ("", null, "") → ""
@Test fun artKeyDiffersByAlbum()                 // mesmo título/artista, álbuns diferentes → chaves diferentes
@Test fun positionAdvancesOnlyWhilePlaying()     // 1000 ms, updatedAt 0, now 2000, speed 1 → 3000 tocando; 1000 pausado
@Test fun positionIsClamped()                    // além da duração → duração; negativa → 0; duração 0 não limita por cima
@Test fun statusKeepsLegacyFieldsAndAddsNewOnes()// name/text/playing + artist, albumName, trackNumber, durationMs, positionMs, artKey
@Test fun statusOmitsUnknownValues()             // year 0, track 0, tracks 0, duração 0, sem artista → chaves ausentes; liked ausente sem canLike
```

- [ ] **Step 2: Run** `.superpowers/g :app:testFullDebugUnitTest --tests '*MediaPayloadTest'`. Expected: FAIL (símbolos inexistentes).
- [ ] **Step 3: Implement** `MediaPayload` conforme as regras.
- [ ] **Step 4: Run** o mesmo comando. Expected: PASS. Commit `feat(android): status de mídia com dados da faixa e posição`.

---

### Task 2: Android — sessão de mídia, capa, fila e comandos

**Files:**
- Modify: `android/app/src/main/java/com/nexus/mastersync/services/NotificationRelay.kt`
  - `fun media(command: String, argument: Long = 0): String`;
  - `fun mediaArt(key: String): JSONObject?`;
  - `fun mediaQueue(): JSONObject?`.
- Modify: `android/app/src/full/java/com/nexus/mastersync/services/MirrorNotifications.kt` (`mediaStatus`, `media`, novos `mediaArt` e `mediaQueue`)
- Modify: `android/app/src/main/java/com/nexus/mastersync/NexusApplication.kt` (roteamento de `mediaCommand`, `mediaArtRequest`, `mediaQueueRequest`, ~linhas 451-456)

**Interfaces:**
- Consumes: `MediaPayload`, `MediaSnapshot` (Task 1).

- [ ] **Step 1: Implement** (verificação por build, porque a sessão de mídia só existe no aparelho):
  - `mediaStatus()` monta o `MediaSnapshot` da primeira sessão ativa:
    - metadados: `METADATA_KEY_TITLE`, `ARTIST`, `ALBUM`, `YEAR`, `TRACK_NUMBER`, `NUM_TRACKS` e `DURATION`;
    - estado: posição, velocidade, `lastPositionUpdateTime` (que usa `SystemClock.elapsedRealtime()`) e `playing`;
    - `canSeek` = `ACTION_SEEK_TO` em `actions`;
    - `canLike` = `session.ratingType == Rating.RATING_HEART`, e `liked` = `metadata.getRating(METADATA_KEY_USER_RATING)?.hasHeart()`;
    - `hasQueue` = a fila não está vazia;
    - devolve `MediaPayload.status(snapshot, SystemClock.elapsedRealtime())`.
  - `media(command, argument)` acrescenta `seek` (`seekTo(argument)`), `like` e `unlike` (`setRating(Rating.newHeartRating(true/false))`, só se `canLike`) e `queueItem` (`skipToQueueItem(argument)`, só se o id estiver na fila atual).
  - `mediaArt(key)`: devolve `null` se `key` não for a `artKey` atual ou não houver bitmap (`METADATA_KEY_ALBUM_ART` ou `ART`); senão reduz para no máximo 256 px, comprime em JPEG com qualidade 80, depois 60 e 192 px se passar de 48 KB, e devolve `mediaArt { artKey, mime, data }`.
  - `mediaQueue()`: `mediaQueue { queue: [{id, title}] }` com no máximo `MAX_QUEUE` itens.
  - `NexusApplication.receive`:
    - `mediaCommand` passa `message.optLong("positionMs")` ou `message.optLong("queueId")` como argumento;
    - `mediaArtRequest` e `mediaQueueRequest` respondem com `client.sendTo`;
    - todos sob `options.value.mediaControl`.
- [ ] **Step 2: Run** a verificação completa do Android. Expected: PASS nas duas edições. Commit `feat(android): capa, fila e comandos do player de mídia`.

---

### Task 3: Mac — estado puro do player

**Files:**
- Modify: `macOS/Sources/NexusCore/Wire.swift`
  - `Message`: `artist: String?`, `albumName: String?`, `year: Int?`, `trackNumber: Int?`, `trackCount: Int?`, `durationMs: Int64?`, `positionMs: Int64?`, `speed: Double?`, `artKey: String?`, `canSeek: Bool?`, `canLike: Bool?`, `liked: Bool?`, `hasQueue: Bool?`, `queue: [MediaQueueItem]?`, `queueId: Int64?`;
  - `public struct MediaQueueItem: Codable { public let id: Int64; public let title: String }`.
- Create: `macOS/Sources/NexusMasterSync/MediaPlayerState.swift`
- Test: `macOS/Tests/NexusCoreTests/MediaPlayerStateTests.swift`

**Interfaces:**
- Produces:

```swift
struct MediaPlayerState: Equatable {
    let title: String?, artist: String?, album: String?
    let year: Int?, trackLine: String?
    let durationMs: Int64?, positionMs: Int64, speed: Double, playing: Bool?
    let receivedAt: Date
    let artKey: String?
    let canSeek: Bool, canLike: Bool, liked: Bool, hasQueue: Bool
    var isEmpty: Bool { title == nil && artist == nil }
    init(message: Message, receivedAt: Date)
    func position(at date: Date) -> Int64          // avança se tocando, entre 0 e a duração
    func fraction(at date: Date) -> Double         // 0 sem duração
    nonisolated static func clock(_ ms: Int64) -> String   // "0:56", "3:43", "1:02:03"
    nonisolated static func seekTarget(fraction: Double, durationMs: Int64) -> Int64
}
enum MediaOutput: Equatable { case phone, mac
    nonisolated static func current(audioOnlyActive: Bool) -> MediaOutput }
```

Regras:
- Título: `name`, e o artista: `artist ?? text`. Textos vazios viram `nil`.
- `trackLine`: `"N de M"` com os dois > 0; só N > 0 dá `"Faixa N"`; senão `nil`.
- `year` só se > 0. `durationMs` só se > 0.
- `clock`: minutos:segundos, com horas quando passar de 60 min; valor negativo vira `0:00`.
- `seekTarget`: `fraction` limitada a 0...1 vezes a duração.

- [ ] **Step 1: Write the failing tests:**

```swift
func testLegacyMessageStillParses()              // só name/text/playing → título, artista, sem ano/faixa/duração; isEmpty false
func testFullMessageParses()                     // todos os campos, trackLine "2 de 14", year 2025
func testTrackLineVariants()                     // (2,14)→"2 de 14"; (2,0)→"Faixa 2"; (0,14)→nil
func testPositionAdvancesWhilePlayingAndClamps() // 56_000 ms, tocando, 2 s depois → 58_000; muito depois → duração; pausado fica
func testPositionClampsToDuration()
func testFractionWithoutDurationIsZero()
func testClockFormats()                          // 56_000→"0:56"; 223_000→"3:43"; 3_723_000→"1:02:03"; -5→"0:00"
func testSeekTargetClamps()                      // (0.5, 200_000)→100_000; (1.7, 200_000)→200_000; (-1, …)→0
func testOutputFollowsAudioOnly()                // true→.mac, false→.phone
```

- [ ] **Step 2: Run** `.superpowers/m --filter MediaPlayerStateTests`. Expected: falha de compilação.
- [ ] **Step 3: Implement** os campos de `Message` e `MediaPlayerState`.
- [ ] **Step 4: Run** `.superpowers/m`. Expected: PASS. Commit `feat(mac): estado do player de mídia`.

---

### Task 4: Mac — modelo: capa, fila e comandos

**Files:**
- Modify: `macOS/Sources/NexusMasterSync/NexusModel.swift` (perto de `currentMedia`, ~570, e do `case "mediaStatus"`, ~910)
- Create: `macOS/Sources/NexusMasterSync/MediaCommands.swift`
- Test: `macOS/Tests/NexusCoreTests/MediaCommandsTests.swift`

**Interfaces:**
- Consumes: `MediaPlayerState`, `Message` (Task 3).
- Produces:

```swift
enum MediaCommands {
    nonisolated static func command(_ name: String, positionMs: Int64? = nil, queueId: Int64? = nil) -> Message  // type "mediaCommand", message = name
    nonisolated static func shouldRequestArt(key: String?, cached: Set<String>, pending: Set<String>) -> Bool
    nonisolated static func acceptsArt(key: String?, currentKey: String?, data: String) -> Data?  // nil se a chave não é a atual ou se NexusModel.acceptedIcon recusa
}
// NexusModel
@Published private(set) var mediaArt: [String: NSImage]      // por artKey
@Published private(set) var mediaQueue: [MediaQueueItem]
var currentMediaState: MediaPlayerState?                     // do peer selecionado; nil se não há mídia (isEmpty)
func mediaSeek(toFraction: Double), func mediaLike(_ on: Bool), func mediaQueueRefresh(), func mediaPlay(queueItem: MediaQueueItem)
```

- [ ] **Step 1: Write the failing tests:**

```swift
func testCommandCarriesItsArguments()     // seek 5000 → type "mediaCommand", message "seek", positionMs 5000; queueItem 7 → queueId 7
func testRequestsArtOnlyWhenMissing()     // chave nova → true; já em cache → false; pendente → false; nil/vazia → false
func testStaleArtIsIgnored()              // chave diferente da atual → nil; chave igual e PNG válido em base64 → Data
func testInvalidArtIsRejected()           // base64 inválido, bytes aleatórios e dado grande demais → nil
func testQueueDecodes()                   // Message com queue [{id,title}] faz round trip
```

- [ ] **Step 2: Run** `.superpowers/m --filter MediaCommandsTests`. Expected: falha de compilação.
- [ ] **Step 3: Implement** `MediaCommands`, o estado e as funções do modelo:
  - guarda `mediaReceivedAt[peer]` junto de `mediaStatuses[peer]`;
  - ao receber `mediaStatus` com `artKey` novo, pede a capa uma única vez (`pending`);
  - `case "mediaArt"` e `case "mediaQueue"`, sob a mesma permissão de `mediaStatus` (`mediaControl`), guardam capa e fila;
  - `mediaSeek` calcula `MediaPlayerState.seekTarget`, `mediaLike` envia `like` ou `unlike`, `mediaQueueRefresh` envia `mediaQueueRequest`, e `mediaPlay(queueItem:)` envia `queueItem`;
  - limpa capa e fila ao desconectar o peer.
- [ ] **Step 4: Run** `.superpowers/m`. Expected: PASS. Commit `feat(mac): capa, fila e comandos do player no modelo`.

---

### Task 5: Mac — o cartão translúcido

**Files:**
- Create: `macOS/Sources/NexusMasterSync/MediaPlayerCard.swift`
- Modify: `macOS/Sources/NexusMasterSync/Dashboard.swift`
  - `audioPanel` (~409) passa a conter `MediaPlayerCard` e a linha de volume (só com saída Mac);
  - remove os botões soltos de "Ações no Android" (~1156), mantendo "Tocar telefone" e o feedback.
- Test: `macOS/Tests/NexusCoreTests/MediaPlayerCardRenderTests.swift`

**Interfaces:**
- Produces: `struct MediaPlayerCard: View { let state: MediaPlayerState?; let art: NSImage?; let queue: [MediaQueueItem]; let output: MediaOutput; let connecting: Bool; let canControl: Bool; let palette: NexusPalette; let onCommand: (String) -> Void; let onSeek: (Double) -> Void; let onLike: (Bool) -> Void; let onOpenQueue: () -> Void; let onPick: (MediaQueueItem) -> Void; let onOutput: (MediaOutput) -> Void }`.

- [ ] **Step 1: Write the failing test** `testCardRendersInBothAppearances`: renderiza `MediaPlayerCard` com um estado completo e com `state: nil` via `ImageRenderer` (claro e escuro), e confirma que o `NSImage` existe e que o seu `size` passa de 300×100. Também grava os PNG em `/private/tmp/claude-501/` para inspeção.
- [ ] **Step 2: Run** `.superpowers/m --filter MediaPlayerCardRenderTests`. Expected: falha de compilação.
- [ ] **Step 3: Implement** a view conforme o design:
  - fundo `ultraThinMaterial` com `palette.accentSurface.opacity(0.18)` por cima e borda de 1 pt em `palette.border`; com `accessibilityReduceTransparency` o fundo é `palette.surface`;
  - capa 76 pt com cantos de 14, ou um ícone de nota quando não há imagem;
  - linhas `Artista:`, `Álbum:`, `Ano:` e `N de M`, só as presentes;
  - ♡ quando `canLike`, ☰ quando `hasQueue`, com a lista num `popover`;
  - seletor de saída com dois botões em pílula (`NexusPillStyle(segmented:)`);
  - controles com o play/pause em círculo cheio de 46 pt;
  - barra com `Slider` quando `canSeek`, ou `ProgressView` quando não, com os tempos nas pontas; um `TimelineView(.periodic(from:by: 0.5))` atualiza a posição só enquanto toca;
  - estado vazio: "Nada tocando no Android".
  Ligue no `Dashboard`: saída Mac → `launchScrcpy(audioOnly: true, wireless:)` com o guia quando não há ADB pelo Wi-Fi, saída Celular → `screen.stopUSB()`.
- [ ] **Step 4: Run** `.superpowers/m`. Expected: PASS. Olhar os PNG gerados. Commit `feat(mac): cartão translúcido do player de mídia`.

---

### Task 6: Revisão final

- [ ] Revisão da branch inteira por um revisor independente e correções dos achados importantes. Não gerar ZIP nem instalar APK até o usuário pedir.
