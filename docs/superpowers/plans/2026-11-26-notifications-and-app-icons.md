# Notificações e ícones dos apps fixados: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolver seis coisas:
- notificações fixas podem ser ocultadas no Mac;
- um botão limpa todas as notificações;
- o conteúdo aparece com o celular bloqueado quando a tela de bloqueio do Android também mostraria;
- os apps fixados no Mac aparecem como ícones;
- "Controlar" usa o ADB pelo Wi-Fi, sem autorização no celular e sem cair ao bloquear;
- o atalho de digitalizar abre a câmera direto.

**Architecture:**
- **Mac:** `NotificationSync` ganha estado de ocultação local e `clearAll`, sem mudança de protocolo.
- **Android:** uma regra pura de privacidade substitui o `isDeviceLocked` incondicional.
- **Ícones:** novo par de mensagens, `launcherIconsRequest` e `launcherIcons`, pedido só para os apps fixados, com cache no Mac.

**Tech Stack:** Swift 6 / SwiftUI (pacote `macOS`, XCTest) e Kotlin / Compose (`android`, JUnit + org.json).

**Spec:** `docs/superpowers/specs/2026-11-26-notifications-and-app-icons-design.md`

## Global Constraints

- Frame máximo de 256 KiB nos dois lados. `launcherIconsRequest` leva no máximo 24 componentes, e o ícone é um PNG 48×48 em base64.
- Componente válido segue a regex `\A[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+\z` e tem no máximo 220 bytes, igual a `AndroidApp.validComponent`.
- Mensagem desconhecida é ignorada nos dois lados. Um Android antigo não responde, e o Mac mostra o nome.
- Textos em português do Brasil:
  - "Ocultar no Mac"
  - "Fixa no Android — ocultar só no Mac"
  - "Limpar todas"
  - "Dispensar no Android"
- Verificação no Android: `.superpowers/g :app:testFullDebugUnitTest :app:testDirectDebugUnitTest :app:assembleFullDebug :app:assembleDirectDebug`. O script auxiliar usa o JDK 21, o SDK em `/private/tmp/nexus-android-tools` e a build fora do Desktop.
- Verificação no Mac: `swift test --package-path macOS --scratch-path /private/tmp/claude-501/mac-build`.

## Review Focus

1. Uma notificação fixa ocultada que chega de novo com o mesmo conteúdo, por `notice` ou `noticeSnapshot`, continua oculta. Coberto pelo teste `testSnapshotKeepsHiddenNoticeHidden`.
2. Uma notificação fixa ocultada que sai do Android e volta igual aparece de novo. Coberto pelo teste `testHiddenNoticeForgottenWhenRemoved`.
3. O Mac fica bloqueado com "mostrar conteúdo sensível" desligado no Android, recebendo uma notificação PUBLIC e outra PRIVATE. A PUBLIC mostra o conteúdo e a PRIVATE oculta. Coberto pelo teste `NoticePrivacyTest.lockedPrivateHiddenWhenLockscreenHidesSensitive`.
4. Um pedido de ícones com mais de 24 componentes, com componentes repetidos ou com componentes inválidos é cortado ou filtrado sem quebrar. Coberto pelo teste `LauncherIconsTest`.
5. A resposta de ícones traz um `data` que não é imagem ou que é grande demais, e o Mac descarta esse ícone. Coberto pelo teste `testLauncherIconsRejectInvalidData`.

---

### Task 1: Mac — ocultar fixas e limpar todas

**Files:**
- Modify: `macOS/Sources/NexusMasterSync/NotificationSync.swift`, `macOS/Sources/NexusMasterSync/Dashboard.swift:749-757,762-766,~1000-1015`
- Test: `macOS/Tests/NexusCoreTests/NotificationSyncTests.swift`

**Interfaces:**
- Produces: `NotificationSync.hide(_ entry: Notice)` e `NotificationSync.clearAll(peer: String)`.
- Produces: `private var hidden: [String: String]`. A chave é o id do Notice e o valor é `title + "\u{0}" + body`.

Regras:
- `hide`:
  - grava a assinatura em `hidden`;
  - remove o item de `notices`;
  - remove o item da Central de Notificações do macOS.
- Ao receber um `notice`:
  - se o id está em `hidden` com a mesma assinatura, o notice é ignorado: não entra em `notices` e não é postado;
  - se a assinatura mudou, o id sai de `hidden` e o notice aparece normalmente.
- `noticeRemoved`: limpa `hidden[id]`.
- `applySnapshot`:
  - remove dos entries os ocultos que têm a mesma assinatura;
  - esquece os ids ocultos daquele peer que não vieram no snapshot.
- `clearAll(peer:)`: para cada notice do peer, chama `dismiss` se `canDismiss` e `hide` se não.
- `removePeer` e `removeAll` limpam os ocultos correspondentes.

- [ ] **Step 1: Write the failing tests** em `NotificationSyncTests`. O helper `notice(_:at:)` existe e ganha os parâmetros `canDismiss: Bool = true` e `text: String = "t"`.

```swift
@MainActor func testHiddenFixedNoticeStaysHiddenUntilItChanges()  // hide(fixa) → some; mesmo notice de novo → continua fora; notice com text novo → volta
@MainActor func testHiddenNoticeForgottenWhenRemoved()             // hide → noticeRemoved → mesmo notice de novo → aparece
@MainActor func testSnapshotKeepsHiddenNoticeHidden()               // hide → snapshot completo com o mesmo notice → não aparece
@MainActor func testClearAllDismissesClearableAndHidesFixed()       // 1 clearable + 1 fixa do "phone" + 1 do "other": clearAll("phone") envia 1 noticeDismiss (id da clearable), a fixa some, a do "other" fica
```

Use `sync.enabled = true` e `hideContent = false`. Capture os envios com `sync.send = { peer, message in sent.append(message) }`.

- [ ] **Step 2: Run** `swift test --package-path macOS --scratch-path /private/tmp/claude-501/mac-build --filter NotificationSyncTests`. Expected: falha de compilação (`hide`/`clearAll` não existem).
- [ ] **Step 3: Implement** as regras acima em `NotificationSync.swift`.
- [ ] **Step 4: Run** o mesmo comando. Expected: PASS.
- [ ] **Step 5: UI** em `Dashboard.swift`:
  - `dismissNoticeButton`:
    - se `canDismiss`: `xmark.circle` com a dica "Dispensar no Android", chamando `dismiss`;
    - se não: `eye.slash` com a dica e a acessibilidade "Fixa no Android — ocultar só no Mac", chamando `hide`;
    - o botão nunca fica desabilitado.
  - Botão "Limpar todas" (`Label("Limpar todas", systemImage: "xmark.bin")`, estilo `NexusPillStyle(compact: true)`):
    - no `HStack` do card compacto, depois de "Ver todas";
    - no cabeçalho da seção completa de notificações;
    - chama `model.notifications.clearAll(peer:)` com o peer selecionado;
    - fica desabilitado quando não há notices.
- [ ] **Step 6: Run** a suíte completa do Mac. Expected: tudo PASS. Commit `feat(mac): ocultar notificações fixas e limpar todas`.

---

### Task 2: Android — conteúdo segue a regra da tela de bloqueio

**Files:**
- Create: `android/app/src/main/java/com/nexus/mastersync/services/NoticePrivacy.kt`
- Modify: `android/app/src/full/java/com/nexus/mastersync/services/MirrorNotifications.kt:211-213` (`privateContent`)
- Test: `android/app/src/test/java/com/nexus/mastersync/services/NoticePrivacyTest.kt`

**Interfaces:**
- Produces: `object NoticePrivacy { fun redact(hideAll: Boolean, visibility: Int, locked: Boolean, lockscreenAllowsPrivate: Boolean): Boolean }`. `visibility` usa as constantes de `Notification`: `VISIBILITY_SECRET = -1`, `VISIBILITY_PRIVATE = 0` e `VISIBILITY_PUBLIC = 1`.

A regra:

```
hideAll || visibility == SECRET || (locked && !lockscreenAllowsPrivate && visibility != PUBLIC)
```

- [ ] **Step 1: Write the failing tests**

```kotlin
@Test fun unlockedShowsContent() = assertFalse(NoticePrivacy.redact(false, 0, locked = false, lockscreenAllowsPrivate = false))
@Test fun hideAllAlwaysRedacts() = assertTrue(NoticePrivacy.redact(true, 1, locked = false, lockscreenAllowsPrivate = true))
@Test fun secretAlwaysRedacts() = assertTrue(NoticePrivacy.redact(false, -1, locked = false, lockscreenAllowsPrivate = true))
@Test fun lockedShowsWhenLockscreenShowsSensitive() = assertFalse(NoticePrivacy.redact(false, 0, locked = true, lockscreenAllowsPrivate = true))
@Test fun lockedPrivateHiddenWhenLockscreenHidesSensitive() {
    assertTrue(NoticePrivacy.redact(false, 0, locked = true, lockscreenAllowsPrivate = false))
    assertFalse(NoticePrivacy.redact(false, 1, locked = true, lockscreenAllowsPrivate = false))
}
```

- [ ] **Step 2: Run** `.superpowers/g :app:testFullDebugUnitTest --tests '*NoticePrivacyTest'`. Expected: FAIL, porque o símbolo não existe.
- [ ] **Step 3: Implement** `NoticePrivacy.redact`. Em `privateContent`, chamar a função com `nexus.options.value.hideNotifications`, `sbn.notification.visibility` e `isDeviceLocked`, e com `Settings.Secure.getInt(contentResolver, "lock_screen_allow_private_notifications", 1) != 0`, que é a chave do sistema. Se a leitura falhar, tratar como `false`, o lado seguro.
- [ ] **Step 4: Run** a verificação completa do Android. Expected: PASS. Commit `fix(android): conteúdo de notificações segue a tela de bloqueio`.

---

### Task 3: Android — responder ícones dos apps

**Files:**
- Create: `android/app/src/main/java/com/nexus/mastersync/services/LauncherIcons.kt`
- Modify: `android/app/src/main/java/com/nexus/mastersync/NexusApplication.kt`, junto do caso `"launcherAppsRequest"` (~linha 413)
- Test: `android/app/src/test/java/com/nexus/mastersync/services/LauncherIconsTest.kt`

**Interfaces:**
- Produces: `object LauncherIcons { const val MAX = 24; const val SIZE = 48; fun requested(message: JSONObject): List<String> }`. A função lê `components` (JSONArray), filtra pela regex de componente com no máximo 220 bytes, remove repetidos mantendo a ordem e corta em `MAX`.
- Produces (protocolo):
  - pedido: `launcherIconsRequest { components: [String] }`;
  - resposta: `launcherIcons { launcherIcons: [{ component, data }] }`.

- [ ] **Step 1: Write the failing tests**

```kotlin
@Test fun keepsValidDistinctInOrder()   // ["a.b/.C", "a.b/.C", "x.y/z.W"] → ["a.b/.C", "x.y/z.W"]
@Test fun dropsInvalid()                // ["sem barra", "a/b c", "../x"] → []
@Test fun capsAtMax()                   // 30 válidos → 24
@Test fun missingArrayIsEmpty()         // JSONObject() → []
```

- [ ] **Step 2: Run** `.superpowers/g :app:testFullDebugUnitTest --tests '*LauncherIconsTest'`. Expected: FAIL.
- [ ] **Step 3: Implement** `requested`, depois o caso `"launcherIconsRequest"` em `NexusApplication`:
  - aceita só componentes presentes em `queryIntentActivities(ACTION_MAIN + CATEGORY_LAUNCHER)`;
  - `loadIcon` → bitmap 48×48 → PNG → `Wire.encode`, como o `icon()` de `MirrorNotifications`;
  - envia a resposta com `client.sendTo(peer, …)`;
  - roda numa thread de I/O se o handler já for de fundo; senão, mantém o padrão do caso vizinho.
- [ ] **Step 4: Run** a verificação completa do Android. Expected: PASS. Commit `feat(android): envia ícones dos apps pedidos pelo Mac`.

---

### Task 4: Mac — ícones nos apps fixados

**Files:**
- Modify: `macOS/Sources/NexusCore/Wire.swift`
  - em `Message`: `public var components: [String]?` e `public var launcherIcons: [AndroidAppIcon]?`;
  - nova `public struct AndroidAppIcon: Codable { public let component: String; public let data: String }`.
- Modify: `macOS/Sources/NexusMasterSync/NexusModel.swift`, perto de `launcherLists` (~559) e do `case "launcherApps"` (~757)
- Modify: `macOS/Sources/NexusMasterSync/Dashboard.swift:298-308`
- Test: `macOS/Tests/NexusCoreTests/WireTests.swift` e `macOS/Tests/NexusCoreTests/LauncherIconCacheTests.swift`

**Interfaces:**
- Consumes: o protocolo da Task 3.
- Produces:
  - `@Published private(set) var launcherIcons: [String: NSImage]`, carregado das preferências `"launcher-icons"` (`[String: Data]` em JSON);
  - `func requestLauncherIcons(for pins: [String])`;
  - `static func missingIcons(pins: [String], cached: Set<String>) -> [String]`: devolve os pins válidos que não estão no cache, sem repetição e com no máximo 24;
  - `static func acceptedIcon(_ base64: String) -> Data?`: aceita só dados de no máximo 64 KiB que `NSImage(data:)` consegue abrir.

- [ ] **Step 1: Write the failing tests**

```swift
func testLauncherIconsRoundTrip()                 // WireTests: Message("launcherIcons") com 1 AndroidAppIcon codifica/decodifica igual
func testMissingIconsSkipsCachedInvalidAndCaps() // 30 pins (1 inválido, 2 já no cache, 1 repetido) → 24 válidos sem cache
func testLauncherIconsRejectInvalidData()          // acceptedIcon("não-base64") == nil; base64 de bytes aleatórios == nil; PNG 1×1 válido != nil
```

- [ ] **Step 2: Run** `swift test … --filter 'WireTests|LauncherIconCacheTests'`. Expected: falha de compilação.
- [ ] **Step 3: Implement**:
  - as funções estáticas e o estado em `NexusModel`;
  - o `case "launcherIcons"` com o mesmo gate do `launcherApps`, `permissions[peer]?.launcher == true`. Ele só aceita componentes que estão em `launcherLists[peer]`, passa os dados por `acceptedIcon`, guarda no cache e persiste.
- [ ] **Step 4: UI.** Na grade dos fixados:
  - com ícone em cache: botão com `Image(nsImage:)` de 32 pt, `.help(label)` e `.accessibilityLabel(label)`, sem texto;
  - sem ícone: a pílula com o nome, como hoje;
  - `.task(id: pins)` chama `model.requestLauncherIcons(for: pins)`.
- [ ] **Step 5: Run** a suíte do Mac e `./scripts/build-macos.sh`. Expected: PASS e o build OK. Commit `feat(mac): ícones nos apps do Android fixados`.

---

### Task 5: Mac — "Controlar" pelo scrcpy quando há ADB pelo Wi-Fi

**Files:**
- Modify: `macOS/Sources/NexusMasterSync/ScreenMirror.swift`
  - adicionar `enum ControlRoute: Equatable { case scrcpy, mirror }`;
  - adicionar `static func controlRoute(hasWirelessADB: Bool, scrcpyInstalled: Bool) -> ControlRoute`.
- Modify: `macOS/Sources/NexusMasterSync/Dashboard.swift`
  - `embeddedControlButton` (~572);
  - o botão do guia (~1354).
- Modify: `macOS/Sources/NexusMasterSync/NexusModel.swift`
  - `launchAndroidApp` (~570).
- Test: `macOS/Tests/NexusCoreTests/ControlRouteTests.swift`

- [ ] **Step 1: Write the failing test.** `testScrcpyOnlyWithWirelessAndScrcpy` cobre as 4 combinações. Só `(true, true)` devolve `.scrcpy`.
- [ ] **Step 2: Run** `swift test … --filter ControlRouteTests`. Expected: falha de compilação.
- [ ] **Step 3: Implement.**
  - Os dois botões chamam `screen.launchScrcpy(audioOnly: false, wireless: device)` quando a rota é `.scrcpy`. Se não, mantêm `beginControl`.
  - `launchAndroidApp` com `.scrcpy`:
    - resolve o serial com `wirelessSerial(for:)` fora da main thread;
    - roda `openApp(app, serial:)`;
    - chama `launchScrcpy`, a menos que o scrcpy já esteja aberto;
    - em caso de erro, mostra o feedback em `screen.feedback`.
- [ ] **Step 4: Run** a suíte do Mac. Expected: PASS. Commit `feat(mac): controlar pelo ADB sem autorização no celular`.

---

### Task 6: Digitalizar abre a câmera direto pelo ADB

**Files:**
- Create: `android/app/src/main/java/com/nexus/mastersync/services/ScanAutoAccept.kt`
  - `class ScanAutoAccept(private val windowMs: Long = 20_000)`;
  - `fun expect(id: String, now: Long)`;
  - `fun consume(id: String?, now: Long): Boolean`: devolve `true` uma vez para o id esperado dentro da janela e depois esquece. Ids inválidos (`Wire.validID`) nunca são esperados.
- Modify:
  - `android/app/src/main/java/com/nexus/mastersync/NexusApplication.kt`: `val scanAutoAccept = ScanAutoAccept()` no `NexusController`;
  - `android/app/src/main/java/com/nexus/mastersync/MainActivity.kt`:
    - `handle()` lê a extra `accept-scan` e chama `expect`;
    - um coletor de `nexus.pendingScan` (em `repeatOnLifecycle(STARTED)`) chama `actions.acceptScan(false)` quando `consume(request.id, SystemClock.elapsedRealtime())` dá `true`;
  - `android/app/src/main/java/com/nexus/mastersync/ui/NexusScreen.kt`: o diálogo de digitalização não aparece enquanto o aceite automático está em andamento. Expor `NexusController.autoAcceptingScan: StateFlow<Boolean>`, ou o executor pode usar uma regra equivalente.
  - `macOS/Sources/NexusMasterSync/ADBClipboard.swift`:
    - `func openScanCamera(serial: String, requestID: String) throws`;
    - roda `am start -n '<pkg>/com.nexus.mastersync.MainActivity' --es accept-scan '<id>'` para `pkg` em `com.nexus.mastersync` e depois `com.nexus.mastersync.direct`, e para no primeiro que der certo;
    - o id precisa passar por `Wire.validID`.
  - `macOS/Sources/NexusMasterSync/NexusModel.swift`:
    - depois de cada envio de `scanRequest` (em `requestScanPaste` e em qualquer outro remetente de `scanRequest`), se `wirelessControlDevice(for: peer)` existir, resolve o serial e chama `openScanCamera` fora da main thread;
    - o feedback vira "Abrindo a câmera no Android…";
    - se falhar, continua o feedback atual ("Confirme a digitalização no Android.").
- Test:
  - `android/app/src/test/java/com/nexus/mastersync/services/ScanAutoAcceptTest.kt`;
  - `macOS/Tests/NexusCoreTests/ScanCameraCommandTests.swift` (ver abaixo).

- [ ] **Step 1: Write the failing tests**

```kotlin
@Test fun acceptsExpectedIdOnceWithinWindow()   // expect(id, 0); consume(id, 1000) == true; consume(id, 1001) == false
@Test fun expiresAfterWindow()                  // expect(id, 0); consume(id, 20_001) == false
@Test fun ignoresOtherAndNullIds()              // expect(id, 0); consume(outro, 1) == false; consume(null, 1) == false
@Test fun rejectsInvalidId()                    // expect("../x", 0); consume("../x", 1) == false
```

```swift
func testScanCameraArgumentsQuoteComponentAndId()   // ADBClipboardSession.scanCameraArguments(serial:"s", package:"com.nexus.mastersync", id: id) contém "-n", "'com.nexus.mastersync/com.nexus.mastersync.MainActivity'", "--es", "accept-scan", "'\(id)'"
func testScanCameraRejectsInvalidId()               // scanCameraArguments(..., id: "a b") == nil
```

  (`static func scanCameraArguments(serial: String, package: String, id: String) -> [String]?` fica no `ADBClipboard.swift`, e `openScanCamera` usa essa função.)

- [ ] **Step 2: Run** os dois filtros. Expected: falha de compilação.
- [ ] **Step 3: Implement** como descrito em Files.
- [ ] **Step 4: Run** a verificação completa do Android e a suíte do Mac. Expected: PASS. Commit `feat: digitalizar abre a câmera direto pelo ADB`.

---

### Task 7: Verificação no aparelho

- [ ] Instalar o APK full no celular por USB (`/opt/homebrew/bin/adb install -r`) e abrir o app do Mac novo.
- [ ] Notificação fixa (Spotify): o ✕ vira "Ocultar no Mac" e some. Trocar de música (o conteúdo muda) faz ela reaparecer.
- [ ] "Limpar todas": a notificação de teste (`cmd notification post`) sai do celular, e as fixas somem só do Mac.
- [ ] Com o celular bloqueado e as duas opções "Ocultar conteúdo" desligadas, uma notificação nova mostra o texto no Mac.
- [ ] Fixar um app no Mac mostra o ícone dele, com o nome no hover.
- [ ] "Controlar" abre o scrcpy sem pedir nada no celular. Bloquear o celular deixa a janela aberta com a tela de bloqueio.
- [ ] ⌃⌥⌘D com o celular desbloqueado abre a câmera direto, sem o aviso. A foto chega ao Mac e é colada.
