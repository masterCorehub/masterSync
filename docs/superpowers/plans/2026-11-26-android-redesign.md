# Reformulação do app Android — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Substituir a interface do app Android por 3 abas (Início, Conversa, Conexão). O Início ganha um painel de recursos que mostra o que falta para cada um funcionar, e o app passa a usar a identidade visual do app do Mac.

**Architecture:** Só a camada `ui/` é reescrita. Ela se divide em tema, componentes, uma lógica pura de catálogo de recursos e da linha do tempo (com testes de JVM) e quatro telas. O `MainActivity` passa um único `NexusActions` para a tela. Serviços, protocolo e `LocalClient` não mudam. A única mudança de dados acrescenta horário e tamanho opcionais ao histórico de chat e de enviados.

**Tech Stack:** Kotlin, Jetpack Compose, Material 3 (BOM 2025.10.01), JUnit 4 + org.json nos testes de unidade.

**Spec:** `docs/superpowers/specs/2026-11-26-android-redesign-design.md`

## Global Constraints

- minSdk 29, compileSdk 36, JDK 17. Não adicionar dependências novas (os ícones usam `material-icons-core`).
- Duas edições: `full` (`BuildConfig.NOTIFICATION_RELAY = true`) e `direct` (`false`). Notificações e Controle de mídia somem na `direct`.
- Todo texto visível em português do Brasil, curto, no tom do app do Mac.
- Paleta (claro / escuro), copiada de `NexusAppearance.swift`: canvas F5EEE6/191412, surface FFF9F2/2F2521, control ECE0D3/392E28, border DED0C2/59453B, ink 281C16/F5ECE3, muted 635046/C4B1A3, accent 8A4925/F3BB7D, accentInk FFF8F0/27180F, accentSurface F2E0CB/473225, connected 386342/A6CD9E.
- Sem cores dinâmicas do Android. Tema por `options.theme` (`system` / `light` / `dark`).
- Cada configuração existe em um único lugar na interface (antiobjetivo do spec).
- Não mudar protocolo, `LocalClient`, serviços, nem limites de histórico (400 mensagens / 150 enviados).
- Comando de verificação (rodar em `android/`): `./gradlew :app:testFullDebugUnitTest :app:testDirectDebugUnitTest :app:assembleFullDebug :app:assembleDirectDebug`

## Review Focus

1. **Edição direct:** sem o recurso Notificações e sem `mediaControl` no catálogo. Teste em `FeatureCatalogTest` (Task 3).
2. **Mac desconectado:** passos "Ligado no Mac" viram `AwaitingMac` e não deixam o recurso como pendente. Teste em `FeatureCatalogTest` (Task 3).
3. **Histórico antigo sem `time`/`size`:** é lido sem erro, com `0`, e vai para o topo da conversa. Testes em `HistoryCodecTest` (Task 1) e `TimelineTest` (Task 4).
4. **Aba salva com nome antigo** (`Scan`, `Share`, `Devices`, `Settings`) ao restaurar o estado depois de uma atualização: mapeia para a aba nova certa, sem quebrar. Teste em `TabTest` (Task 6).
5. **Arquivo compartilhado de outro app com Arquivos desligado ou Mac desconectado:** o cartão "Pronto para enviar" fica visível, o envio desabilitado e um aviso aponta o que resolver. Teste de `chatBlocker` em `TimelineTest` (Task 4).

---

## Estrutura de arquivos

Base: `android/app/src/main/java/com/nexus/mastersync/` (abreviado `M/`) e `android/app/src/test/java/com/nexus/mastersync/` (abreviado `T/`).

| Arquivo | Responsabilidade |
| --- | --- |
| `M/NexusApplication.kt` (mod.) | `ChatEntry.time` + codec JSON |
| `M/services/TransferQueue.kt` (mod.) | `Sent.time`, `Sent.size` + codec JSON |
| `M/ui/theme/NexusTheme.kt` | paleta, `NexusTheme`, `LocalNexusColors`, `NexusBackdrop` |
| `M/ui/components/Components.kt` | `Pill`, `NexusPanel`, `StatusChip`, `ToggleRow`, `Banner`, `SectionLabel` |
| `M/ui/features/FeatureCatalog.kt` | modelo + `buildFeatures(...)` (puro) |
| `M/ui/features/SystemAccessState.kt` | `rememberSystemAccess()` (lê permissões no `onResume`) |
| `M/ui/conversation/Timeline.kt` | `TimelineItem`, `timeline(...)`, `chatBlocker(...)` (puro) |
| `M/ui/components/StepRow.kt` | linha de passo do painel (usa tipos do catálogo) |
| `M/ui/Navigation.kt` | `enum Tab`, `Tab.restore(name)` |
| `M/ui/NexusActions.kt` | data class com as ações vindas do `MainActivity` |
| `M/ui/home/HomeScreen.kt` | cartão do Mac + lista de recursos |
| `M/ui/sheet/FeatureSheet.kt` | painel deslizante do recurso, com segundos níveis (apps, digitalizações) |
| `M/ui/conversation/ConversationScreen.kt` | linha do tempo + barra de escrita + cartão de arquivo compartilhado |
| `M/ui/connection/ConnectionScreen.kt` | Macs, Ler QR, segundo plano, aparência |
| `M/ui/NexusScreen.kt` (reescrito) | `Scaffold`, abas, faixas globais, roteamento, diálogos de pedido do Mac |
| `M/MainActivity.kt` (mod.) | monta `NexusActions`, `openFeature`, pontos de entrada |

---

### Task 1: Horário e tamanho no histórico

**Files:**
- Modify: `M/NexusApplication.kt:66-111` (ChatEntry, readChat, saveChat, sendChat, receiveChat)
- Modify: `M/services/TransferQueue.kt:29,52-65` (Sent, readSent, recordSent)
- Test: `T/HistoryCodecTest.kt`

**Interfaces:**
- Produces: `NexusController.ChatEntry(peer, id, text, outgoing, confirmed, time: Long = 0)`; `ChatEntry.toJson(): JSONObject`; `ChatEntry.Companion.fromJson(JSONObject): ChatEntry`.
- Produces: `TransferQueue.Sent(peer: String, name: String, time: Long = 0, size: Long = 0)`; `Sent.toJson()`; `Sent.Companion.fromJson(JSONObject)`.

- [ ] **Step 1: Write the failing tests** em `T/HistoryCodecTest.kt`

```kotlin
@Test fun chatEntryRoundTripKeepsTime() {
    val e = NexusController.ChatEntry("p", "id1", "oi", true, false, time = 1_700_000_000_000)
    assertEquals(e, NexusController.ChatEntry.fromJson(e.toJson()))
}
@Test fun legacyChatEntryWithoutTimeReadsAsZero() {
    val json = JSONObject("""{"peer":"p","id":"i","text":"t","outgoing":false,"confirmed":true}""")
    assertEquals(0L, NexusController.ChatEntry.fromJson(json).time)
}
@Test fun sentRoundTripKeepsTimeAndSize() {
    val s = TransferQueue.Sent("p", "a.pdf", time = 5, size = 2_100_000)
    assertEquals(s, TransferQueue.Sent.fromJson(s.toJson()))
}
@Test fun legacySentWithoutTimeAndSizeReadsAsZero() {
    val s = TransferQueue.Sent.fromJson(JSONObject("""{"peer":"p","name":"a.pdf"}"""))
    assertEquals(0L, s.time); assertEquals(0L, s.size)
}
```

- [ ] **Step 2: Run** `./gradlew :app:testFullDebugUnitTest --tests '*HistoryCodecTest'`. Expected: FAIL (`fromJson` / `time` não existem).
- [ ] **Step 3: Implement.** Adicionar os campos com padrão `0`. Ler com `optLong("time", 0)` e `optLong("size", 0)`. `readChat`/`saveChat`/`readSent`/`recordSent` passam a usar o codec. `sendChat` e `receiveChat` gravam `System.currentTimeMillis()`. `recordSent` grava `System.currentTimeMillis()` e `item.size`. A atualização de `confirmed` usa `copy`, que preserva `time`.
- [ ] **Step 4: Run** o mesmo comando. Expected: PASS. Depois, rodar o comando de verificação completo: PASS.
- [ ] **Step 5: Commit** `feat(android): guarda horário e tamanho no histórico de chat e envios`

---

### Task 2: Tema e componentes

**Files:**
- Create: `M/ui/theme/NexusTheme.kt`, `M/ui/components/Components.kt`

**Interfaces:**
- Produces: `data class NexusColors(canvas, surface, control, border, ink, muted, accent, accentInk, accentSurface, connected: Color)`; `val LightNexusColors`, `val DarkNexusColors`; `val LocalNexusColors: ProvidableCompositionLocal<NexusColors>`; `@Composable fun NexusTheme(dark: Boolean, content: @Composable () -> Unit)`, que também monta o `ColorScheme` do Material 3 (primary=accent, onPrimary=accentInk, primaryContainer=accentSurface, background=canvas, surface=surface, surfaceVariant=control, onSurface=ink, onSurfaceVariant=muted, outline=border); `@Composable fun NexusBackdrop(modifier: Modifier)`.
- Produces (componentes):
  - `Pill(text: String, onClick: () -> Unit, prominent: Boolean = false, enabled: Boolean = true)`
  - `NexusPanel(modifier: Modifier = Modifier, highlighted: Boolean = false, content: @Composable ColumnScope.() -> Unit)`
  - `enum class ChipTone { Ok, Warn, Off }`; `StatusChip(text: String, tone: ChipTone)`
  - `ToggleRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, subtitle: String? = null)`
  - `Banner(text: String, action: String, onAction: () -> Unit)`
  - `SectionLabel(text: String)`

- [ ] **Step 1: Implement** os dois arquivos. Painel: raio 19 dp, `surface` e borda `border` com alpha 0.65. Destacado: `accentSurface` e borda `accent` com alpha 0.5. Pílula: formato `CircleShape`, altura mínima 40 dp, preenchida com `accent`/`accentInk` quando `prominent`, senão `control`/`ink`. Chips: Ok usa `connected` sobre `connected` com alpha 0.16; Warn usa `accent` sobre `accentSurface`; Off usa `muted` sobre `control`. Backdrop: `canvas` + `Brush.radialGradient` de `accent` (alpha 0.09 no claro e 0.145 no escuro) centrado em (0.82 w, 0.11 h), raio 540 dp, omitido quando `Settings.Global.TRANSITION_ANIMATION_SCALE == 0`.
- [ ] **Step 2: Run** o comando de verificação. Expected: BUILD SUCCESSFUL.
- [ ] **Step 3: Commit** `feat(android): tema e componentes no visual do app do Mac`

---

### Task 3: Catálogo de recursos

**Files:**
- Create: `M/ui/features/FeatureCatalog.kt`, `M/ui/features/SystemAccessState.kt`
- Test: `T/ui/FeatureCatalogTest.kt`

**Interfaces:**
- Consumes: `NexusController.Options`, `NexusController.Permissions`.
- Produces:

```kotlin
enum class FeatureId { Clipboard, Files, Gallery, Notifications, Mirror, Scan, FindPhone }
enum class StepState { Done, Pending, AwaitingMac }
enum class StepAction { OpenAppSettings, OpenNotificationAccess, RequestGallery, ToggleBackground, EnableFiles }
data class Requirement(val label: String, val chip: String, val hint: String?, val state: StepState,
                       val action: StepAction?, val optional: Boolean = false)
sealed interface FeatureStatus { data object Off : FeatureStatus; data object Active : FeatureStatus
                                 data class Pending(val requirement: Requirement) : FeatureStatus }
data class Feature(val id: FeatureId, val title: String, val summary: String, val enabled: Boolean,
                   val requirements: List<Requirement>, val status: FeatureStatus)
data class SystemAccess(val camera: Boolean, val mediaFull: Boolean, val mediaPartial: Boolean,
                        val appNotifications: Boolean, val notificationListener: Boolean)
fun buildFeatures(options: NexusController.Options, permissions: NexusController.Permissions,
                  connected: Boolean, background: Boolean, access: SystemAccess,
                  notificationRelay: Boolean): List<Feature>
@Composable fun rememberSystemAccess(): SystemAccess   // relê em cada onResume (LifecycleResumeEffect)
```

Regras:
- Chave principal → `enabled`: Clipboard=`clipboard`, Files=`files`, Gallery=`gallery`, Notifications=`notificationMirror`, Mirror=`mirror`, Scan=`remoteScan`, FindPhone=`findPhone`.
- `status`: `Off` se `!enabled`. Senão, `Pending(primeiro requisito com state == Pending && !optional)`. Senão, `Active`.
- Requisito "Ligado no Mac": `Done` se `connected && permission.X`, `AwaitingMac` se `!connected`, `Pending` se conectado e falso. `action = null`, `hint = "No Mac: <caminho>"`, `chip = "Ligar no Mac"`. Caminhos: Clipboard "Celular → Área de transferência", Files "Galeria → Arquivos", Gallery "Galeria → Galeria", Notifications "Celular → Notificações".
- Requisitos por recurso, nesta ordem (★ = `optional`):
  - Clipboard: Mac(`clipboard`); segundo plano★ (`ToggleBackground`, chip "Manter conectado")
  - Files: Mac(`files`)
  - Gallery: fotos e vídeos (`mediaFull || mediaPartial`, `RequestGallery`, chip "Permitir fotos"); Mac(`gallery`); segundo plano★
  - Notifications (só se `notificationRelay`): acesso às notificações (`notificationListener`, `OpenNotificationAccess`, chip "Dar acesso"); Mac(`notifications`); notificações do app (`appNotifications`, `OpenAppSettings`, chip "Permitir avisos"); segundo plano (`ToggleBackground`)
  - Mirror: notificações do app; segundo plano
  - Scan: câmera (`camera`, `OpenAppSettings`, chip "Permitir câmera"); Arquivos no Android (`options.files`, `EnableFiles`, chip "Ligar Arquivos"); Mac(`files`)
  - FindPhone: notificações do app

- [ ] **Step 1: Write the failing tests** (`allOn` = todas as opções true, `perms` = todas true, `access` = tudo true)

```kotlin
@Test fun directEditionHasNoNotificationsFeature() =
    assertTrue(buildFeatures(allOn, perms, true, true, access, notificationRelay = false).none { it.id == FeatureId.Notifications })
@Test fun everythingGrantedIsActive() =
    assertTrue(buildFeatures(allOn, perms, true, true, access, true).all { it.status == FeatureStatus.Active })
@Test fun switchedOffFeatureIsOff() =
    assertEquals(FeatureStatus.Off, feature(FeatureId.Files, allOn.copy(files = false)).status)
@Test fun macOfflineIsAwaitingNotPending() {
    val f = feature(FeatureId.Files, allOn, connected = false, perms = NexusController.Permissions())
    assertEquals(StepState.AwaitingMac, f.requirements.single().state)
    assertEquals(FeatureStatus.Active, f.status)
}
@Test fun macConnectedButDisabledIsPendingWithoutAction() {
    val s = feature(FeatureId.Clipboard, allOn, perms = perms.copy(clipboard = false)).status as FeatureStatus.Pending
    assertEquals("Ligar no Mac", s.requirement.chip); assertNull(s.requirement.action)
}
@Test fun galleryFirstPendingIsMediaPermission() {
    val s = feature(FeatureId.Gallery, allOn, access = access.copy(mediaFull = false, mediaPartial = false)).status
    assertEquals(StepAction.RequestGallery, (s as FeatureStatus.Pending).requirement.action)
}
@Test fun partialMediaCountsAsGranted() =
    assertEquals(FeatureStatus.Active, feature(FeatureId.Gallery, allOn, access = access.copy(mediaFull = false, mediaPartial = true)).status)
@Test fun optionalBackgroundDoesNotMakeClipboardPending() =
    assertEquals(FeatureStatus.Active, feature(FeatureId.Clipboard, allOn, background = false).status)
@Test fun mirrorRequiresBackground() =
    assertEquals(StepAction.ToggleBackground, (feature(FeatureId.Mirror, allOn, background = false).status as FeatureStatus.Pending).requirement.action)
@Test fun scanMainSwitchIsRemoteScan() {
    assertEquals(FeatureStatus.Off, feature(FeatureId.Scan, allOn.copy(remoteScan = false)).status)
    assertNotEquals(FeatureStatus.Off, feature(FeatureId.Scan, allOn.copy(autoScan = false)).status)
}
```

(`feature(id, options, connected = true, background = true, perms = perms, access = access)` é um helper do teste que chama `buildFeatures(..., notificationRelay = true)` e pega o recurso pelo id.)

- [ ] **Step 2: Run** `./gradlew :app:testFullDebugUnitTest --tests '*FeatureCatalogTest'`. Expected: FAIL (símbolos inexistentes).
- [ ] **Step 3: Implement** `buildFeatures` e `rememberSystemAccess`. Mover para `rememberSystemAccess` a leitura de permissões que hoje está em `SettingsPage` (`NexusScreen.kt` linhas 441-473 do arquivo atual). Títulos e resumos: "Área de transferência" / "Copie aqui, cole no Mac", "Arquivos" / "Envie e receba arquivos", "Galeria" / "Fotos e vídeos no Mac", "Notificações" / "Veja e responda avisos do celular no Mac", "Espelhar tela" / "Mostre a tela do celular no Mac", "Digitalizar e câmera" / "O Mac pede, o celular fotografa", "Localizar celular" / "O Mac faz o celular tocar".
- [ ] **Step 4: Run** o mesmo comando. Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): catálogo de recursos com estado e passos`

---

### Task 4: Linha do tempo e bloqueios do chat

**Files:**
- Create: `M/ui/conversation/Timeline.kt`
- Test: `T/ui/TimelineTest.kt`

**Interfaces:**
- Consumes: `ChatEntry`, `TransferQueue.Sent`, `TransferQueue.Received` (Task 1).
- Produces:

```kotlin
sealed interface TimelineItem { val time: Long
  data class Message(val entry: NexusController.ChatEntry) : TimelineItem
  data class SentFile(val sent: TransferQueue.Sent) : TimelineItem
  data class ReceivedFile(val received: TransferQueue.Received, override val time: Long) : TimelineItem }
fun timeline(peer: String?, messages: List<ChatEntry>, sent: List<Sent>, received: List<Received>,
             modified: (File) -> Long = File::lastModified): List<TimelineItem>
enum class ChatBlocker { Disconnected, ChatOffOnMac, FilesOff }
fun chatBlocker(connected: Boolean, options: NexusController.Options, permissions: NexusController.Permissions,
                wantsFiles: Boolean): ChatBlocker?
```

Regras:
- `timeline`: filtra pelo `peer` (`null` → lista vazia). Concatena mensagens, enviados e recebidos, nessa ordem, e aplica `sortedBy { it.time }`, que é estável. Itens com `time == 0` ficam no topo, na ordem original.
- `chatBlocker`: `!connected` → `Disconnected`. Senão, `!permissions.chat` → `ChatOffOnMac`. Senão, se `wantsFiles && !(options.files && permissions.files)` → `FilesOff`. Senão, `null`.

- [ ] **Step 1: Write the failing tests**

```kotlin
// TimelineTest
@Test fun interleavesByTime() { /* msg t=10, sent t=20, received mtime=15 → [msg, received, sent] */ }
@Test fun legacyZeroTimeItemsComeFirstInOriginalOrder() { /* msg t=0 "a", msg t=0 "b", sent t=5 → [a, b, sent] */ }
@Test fun filtersByPeerAndNullPeerIsEmpty() { /* itens de "x" e "y"; peer "x" só mostra "x"; peer null → empty */ }
@Test fun sharedFileWithFilesOffIsBlocked() =
    assertEquals(ChatBlocker.FilesOff, chatBlocker(true, Options(files = false), Permissions(chat = true, files = true), wantsFiles = true))
@Test fun disconnectedWinsOverEverything() =
    assertEquals(ChatBlocker.Disconnected, chatBlocker(false, Options(), Permissions(), wantsFiles = true))
@Test fun textOnlyIgnoresFiles() =
    assertNull(chatBlocker(true, Options(files = false), Permissions(chat = true), wantsFiles = false))
```

Os testes de `timeline` passam `modified = { mtimes[it.name]!! }` e usam `File("x.png")` sem tocar no disco.

- [ ] **Step 2: Run** `./gradlew :app:testFullDebugUnitTest --tests '*TimelineTest'`. Expected: FAIL.
- [ ] **Step 3: Implement** as duas funções. `Message.time = entry.time`, `SentFile.time = sent.time`, `ReceivedFile.time = modified(file)`.
- [ ] **Step 4: Run** o mesmo comando. Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): linha do tempo da conversa`

---

### Task 5: Telas Início, painel do recurso, Conversa e Conexão

**Files:**
- Create: `M/ui/NexusActions.kt`, `M/ui/components/StepRow.kt`, `M/ui/home/HomeScreen.kt`, `M/ui/sheet/FeatureSheet.kt`, `M/ui/conversation/ConversationScreen.kt`, `M/ui/connection/ConnectionScreen.kt`

**Interfaces:**
- Consumes: Tasks 2 a 4.
- Produces:

```kotlin
data class NexusActions(
  val readQr: () -> Unit, val chooseFile: () -> Unit, val toggleBackground: () -> Unit,
  val openNotificationAccess: () -> Unit, val openDndAccess: () -> Unit, val openAppSettings: () -> Unit,
  val requestGallery: () -> Unit, val approvePhoto: () -> Unit, val approveScreen: () -> Unit,
  val keyboardSettings: () -> Unit, val chooseKeyboard: () -> Unit,
  val scan: () -> Unit, val advancedScan: () -> Unit, val acceptScan: (advanced: Boolean) -> Unit,
  val ocr: (ScanLibrary.Document) -> Unit, val dismissOcr: () -> Unit,
  val sendDocument: (ScanLibrary.Document) -> Unit, val export: (File, String, String, Boolean) -> Unit)
@Composable fun StepRow(index: Int, requirement: Requirement, onAction: (StepAction) -> Unit)
@Composable fun HomeScreen(status: LocalClient.Status, background: Boolean, features: List<Feature>,
                           onOpenFeature: (FeatureId) -> Unit, onOpenConnection: () -> Unit, onReadQr: () -> Unit)
@Composable fun FeatureSheet(feature: Feature, nexus: NexusController, actions: NexusActions,
                             documents: List<ScanLibrary.Document>, scannerBusy: Boolean, onDismiss: () -> Unit)
@Composable fun ConversationScreen(nexus: NexusController, actions: NexusActions, shared: Uri?, clearShared: () -> Unit,
                                   onOpenFeature: (FeatureId) -> Unit, onOpenConnection: () -> Unit)
@Composable fun ConnectionScreen(nexus: NexusController, background: Boolean, actions: NexusActions)
```

Conteúdo (o mapeamento completo está nas tabelas do spec, em "Catálogo de recursos"):
- **Home:** `NexusPanel(highlighted = true)` com ponto `connected` e texto "Conectado" ou `status.title`, nome do Mac e "Rede local • em segundo plano" quando `background`. Ao tocar, chama `onOpenConnection`. Sem peers, o painel mostra "Conectar um Mac" e `Pill("Ler QR", prominent)`. Abaixo, `NexusPanel` "Recursos para o Mac" com uma linha por `Feature`: ícone, título e `StatusChip`, sendo `Active` → "Ativo"/Ok, `Pending` → `requirement.chip`/Warn e `Off` → "Desligado"/Off.
- **FeatureSheet:** `ModalBottomSheet` com cabeçalho (título, resumo e `Switch` da chave principal). Ligar Galeria chama `actions.requestGallery`, como hoje. Depois, `SectionLabel("Para funcionar")` + `StepRow` por requisito (Done ✓ `connected`; Pending com número e `Pill(chip)` se `action != null`, senão o `hint`; AwaitingMac em cinza, "Confirme quando o Mac conectar"). Depois, `SectionLabel("Opções")` com as opções do recurso, conforme a tabela do spec. `StepAction.EnableFiles` → `nexus.update(options.copy(files = true))`. Segundo nível por estado local `subpage`: Notificações → lista de apps (`blockedApps`); Digitalizar → "Digitalizações", com as ações da `ScanPage` atual (Salvar PDF, Ler texto, Enviar PDF, páginas JPG/PNG).
- **Conversation:** `LazyColumn` com `timeline(...)` (balões, cartões de arquivo com nome, tamanho formatado por `android.text.format.Formatter.formatShortFileSize` quando `size > 0`, e "Salvar" nos recebidos) + `progress` como cartões com barra. Ao abrir ou receber item, rola até o fim. Barra fixa: `＋` (`chooseFile`), campo (máx. 2048 bytes) e enviar. Faixa de `chatBlocker`: Disconnected → "Mac desconectado", ação "Conectar" → `onOpenConnection`; ChatOffOnMac → "Ative a Conversa no Mac", sem ação; FilesOff → "Arquivos desligado", ação "Abrir" → `onOpenFeature(Files)`. O cartão `shared` aparece acima da barra, com "Enviar ao Mac" desabilitado quando há bloqueio de arquivos.
- **Connection:** painel do Mac atual, "Macs autorizados" (Conectar / Esquecer + diálogo atual), `Pill("Ler QR")`, `ToggleRow("Manter conexão em segundo plano", background) { actions.toggleBackground() }` e aparência (3 `Pill` segmentadas: Automático / Claro / Escuro).

- [ ] **Step 1: Implement** os cinco arquivos. Copiar a lógica de cada ação das funções atuais de `NexusScreen.kt` (`Devices`, `SharePage`, `ScanPage`, `SettingsPage`), sem mudar o comportamento.
- [ ] **Step 2: Run** o comando de verificação. Expected: BUILD SUCCESSFUL, testes PASS.
- [ ] **Step 3: Commit** `feat(android): telas Início, painel de recurso, Conversa e Conexão`

---

### Task 6: Shell nova e ligação no MainActivity

**Files:**
- Rewrite: `M/ui/NexusScreen.kt` (apagar `Home`, `Devices`, `SharePage`, `ScanPage`, `SettingsPage`, helpers e as paletas antigas)
- Modify: `M/MainActivity.kt:44,215,227-247,267,293-301,368,366-391`
- Create: `M/ui/Navigation.kt`
- Test: `T/ui/TabTest.kt`

**Interfaces:**
- Consumes: tudo das Tasks 2 a 5.
- Produces: `enum class Tab(val label: String) { Home("Início"), Conversation("Conversa"), Connection("Conexão"); companion object { fun restore(name: String?): Tab } }`. `restore`: nome novo → a própria aba; `"Share"` → `Conversation`; `"Devices"`/`"Settings"` → `Connection`; `"Scan"`, `null` ou desconhecido → `Home`.
- Produces: `@Composable fun NexusScreen(nexus: NexusController, actions: NexusActions, tab: Tab, navigate: (Tab) -> Unit, openFeature: FeatureId?, setOpenFeature: (FeatureId?) -> Unit, shared: Uri?, clearShared: () -> Unit, documents: List<ScanLibrary.Document>, scannerBusy: Boolean, recognized: String?)`

- [ ] **Step 1: Write the failing test** `T/ui/TabTest.kt`

```kotlin
@Test fun restoresOldNames() {
    assertEquals(Tab.Conversation, Tab.restore("Share")); assertEquals(Tab.Connection, Tab.restore("Devices"))
    assertEquals(Tab.Connection, Tab.restore("Settings")); assertEquals(Tab.Home, Tab.restore("Scan"))
    assertEquals(Tab.Home, Tab.restore(null)); assertEquals(Tab.Home, Tab.restore("???"))
}
```

- [ ] **Step 2: Rewrite `NexusScreen`** e crie `Navigation.kt`, removendo o `enum Tab` antigo de `NexusScreen.kt`. `NexusTheme(dark = ...)` + `NexusBackdrop` atrás de um `Scaffold` transparente. Top bar com logo e "MasterSync", sem engrenagem. `NavigationBar` com 3 abas (ícones Home, Email/Send ou equivalente core, Link/Settings). Faixas globais (`mirroring` → "Sua tela está sendo compartilhada com o Mac." / "Parar"; `feedback` / "Fechar") no topo de qualquer aba. Roteamento das abas. `FeatureSheet` quando `openFeature != null`. Diálogos de espelhamento, foto, digitalização e OCR mantidos como estão, mas chamando `actions`. `BackHandler`: com painel aberto, fecha o painel; numa aba diferente de Início, vai para Início.
- [ ] **Step 3: Rewire `MainActivity`.** `tab` usa o novo `Tab`. Adicionar `private val openFeature = mutableStateOf<FeatureId?>(null)`. Restauração: `Tab.restore(savedInstanceState?.getString("tab"))`. `handle()`: `ACTION_SEND` e `open-share` → `Tab.Conversation`; `open-scan` → `Tab.Home` + `openFeature = FeatureId.Scan`. Em `openDocumentCamera` e na linha 368, trocar `tab.value = Tab.Scan` por `openFeature.value = FeatureId.Scan`. Construir `NexusActions` uma vez, com as funções atuais. `openAppSettings` e `openDndAccess` vêm do código hoje inline em `SettingsPage`.
- [ ] **Step 4: Run** o comando de verificação. Expected: BUILD SUCCESSFUL, todos os testes PASS (inclui `TabTest`), nenhum aviso de símbolo não usado em `ui/`.
- [ ] **Step 5: Verify on device** (emulador ou celular, build `full` e `direct`). Checklist:
  - Início lista 7 recursos na full e 6 na direct.
  - Tocar em Galeria sem permissão mostra "Permitir fotos". A pílula abre o pedido do sistema e, ao voltar, o selo atualiza.
  - Com o Mac desligado, os passos do Mac ficam em cinza.
  - Conversa: mensagem enviada aparece no fim e um arquivo enviado aparece intercalado.
  - Compartilhar um arquivo pelo menu de outro app abre a Conversa com o cartão.
  - Notificação de pedido de digitalização abre o Início com o painel Digitalizar.
  - Tema escuro usa a paleta escura do Mac.
  - Instalar por cima da versão anterior com a aba salva não quebra.
- [ ] **Step 6: Commit** `feat(android): nova navegação em 3 abas com painel de recursos`
