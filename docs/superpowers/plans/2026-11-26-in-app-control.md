# Controle dentro do app: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** "Controlar" mostra o celular numa janelinha dentro do app, sem autorização no celular e sem cair ao bloquear, com toque, rolagem e teclado.

**Architecture:** Partes puras e testadas (leitor do fluxo de vídeo, construtor das mensagens de controle, conversão de H.264 e conversão de coordenadas) e uma parte de execução (cliente do servidor do scrcpy, tela com `AVSampleBufferDisplayLayer`). Um teste opcional, ligado por variável de ambiente, roda a cadeia inteira contra o celular.

**Tech Stack:** Swift, AVFoundation (`AVSampleBufferDisplayLayer`), CoreMedia, soquetes POSIX, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-26-in-app-control-design.md`

## Global Constraints

- Protocolo do scrcpy **5.0.1**, tudo em big-endian. Uma versão diferente do scrcpy instalado deve ser enviada ao servidor como está (o servidor recusa se não bater); o código não assume o número.
- O servidor é lido de `<prefixo do scrcpy>/share/scrcpy/scrcpy-server`, achado a partir do executável `scrcpy` já localizado pelo app (`/opt/homebrew/bin` ou `/usr/local/bin`).
- Todo o trabalho de rede fora da thread principal. Nenhum bloqueio de UI.
- Nenhuma compilação em release nem instalação no aparelho neste plano. A cadeia é verificada pelo teste opcional contra o celular (`NEXUS_SCRCPY_SERIAL=192.168.3.31:5555`) e por `swift test`.
- Verificação: `.superpowers/m`.

## Review Focus

1. O leitor do fluxo recebe os mesmos bytes cortados em qualquer ponto (de 1 em 1 byte, por exemplo) e produz os mesmos eventos. Teste `testParserIsIndependentOfHowBytesAreSplit`.
2. Um tamanho de pacote absurdo (maior que 16 MiB) ou um código de codec desconhecido encerra o fluxo com erro, em vez de alocar memória sem limite. Teste `testParserRejectsHostileSizes`.
3. Cliques nas faixas pretas do enquadramento não geram toque. Teste `testClicksOutsideTheVideoAreIgnored`.
4. Depois de uma rotação (novo pacote de sessão e nova configuração) o vídeo continua. Teste `testSessionPacketResetsTheFormat`.
5. Parar sempre encerra o servidor e remove o túnel, mesmo quando a conexão falha na metade. Teste opcional `testStartAndStopLeaveNothingBehind`.

---

### Task 1: Leitor do fluxo de vídeo do scrcpy (puro)

**Files:**
- Create: `macOS/Sources/NexusMasterSync/ScrcpyStream.swift`
- Test: `macOS/Tests/NexusCoreTests/ScrcpyStreamTests.swift`

**Interfaces:**
- Produces:

```swift
enum ScrcpyEvent: Equatable {
    case deviceName(String)
    case session(width: Int, height: Int)
    case config(Data)                                   // SPS e PPS em Annex B
    case frame(Data, keyFrame: Bool, ptsMicros: UInt64)
}
struct ScrcpyStreamParser {
    init(expectDummyByte: Bool = true)
    mutating func feed(_ data: Data) throws -> [ScrcpyEvent]
}
enum ScrcpyStreamError: Error, Equatable { case unsupportedCodec(UInt32), packetTooLarge(Int), invalidSession }
```

Regras:
- Estados em ordem: byte de teste (opcional), nome do aparelho (64 bytes, UTF-8 até o primeiro zero), código do codec (4 bytes; só `0x68323634`, "h264", é aceito), depois repetições de 12 bytes de cabeçalho.
- Cabeçalho com o primeiro bit do primeiro byte ligado: pacote de sessão; os 4 bytes seguintes são a largura e os últimos 4 são a altura (ambos de 1 a 16384, senão `invalidSession`).
- Senão: 8 bytes `flags/pts` (bit 62 = configuração, bit 61 = quadro-chave, bits 0 a 60 = PTS) e 4 bytes de tamanho, e depois o conteúdo. Tamanho maior que 16 MiB lança `packetTooLarge`.
- Aceita bytes em qualquer fragmentação e guarda o resto entre chamadas.

- [ ] **Step 1: Write the failing tests** em `ScrcpyStreamTests`, com um helper que monta um fluxo sintético:

```swift
func testParsesTheHandshakeAndPackets()            // 0x00 + nome "SM_S916B" + "h264" + sessão 1080x2340 + config + frame-chave + frame normal → eventos nessa ordem, com keyFrame/pts corretos
func testParserIsIndependentOfHowBytesAreSplit()   // o mesmo fluxo, alimentado de 1 em 1 byte e em blocos de 7, dá os mesmos eventos
func testSessionPacketResetsTheFormat()            // dois pacotes de sessão (rotação) com tamanhos diferentes → dois eventos .session
func testParserRejectsHostileSizes()               // tamanho 0x7FFFFFFF → packetTooLarge; codec "av01" → unsupportedCodec; sessão 0x0 → invalidSession
func testWithoutDummyByte()                        // expectDummyByte: false começa direto no nome
```

- [ ] **Step 2: Run** `.superpowers/m --filter ScrcpyStreamTests`. Expected: falha de compilação.
- [ ] **Step 3: Implement** `ScrcpyStreamParser` conforme as regras.
- [ ] **Step 4: Run** `.superpowers/m`. Expected: PASS. Commit `feat(mac): leitor do fluxo de vídeo do scrcpy`.

---

### Task 2: H.264 e mensagens de controle (puros)

**Files:**
- Create: `macOS/Sources/NexusMasterSync/H264.swift`, `macOS/Sources/NexusMasterSync/ScrcpyControl.swift`
- Test: `macOS/Tests/NexusCoreTests/H264Tests.swift`, `macOS/Tests/NexusCoreTests/ScrcpyControlTests.swift`

**Interfaces:**
- Produces:

```swift
enum H264 {
    nonisolated static func nalUnits(in annexB: Data) -> [Data]            // separa por 00 00 01 / 00 00 00 01, sem os códigos
    nonisolated static func lengthPrefixed(fromAnnexB data: Data) -> Data   // cada NAL com 4 bytes de tamanho antes
    nonisolated static func parameterSets(fromConfig data: Data) -> (sps: Data, pps: Data)?   // NAL tipo 7 e tipo 8
}
enum ScrcpyControl {
    nonisolated static let mousePointer: UInt64 = .max
    nonisolated static func keycode(action: UInt8, keycode: Int32, metaState: Int32 = 0) -> Data      // 14 bytes
    nonisolated static func touch(action: UInt8, x: Int32, y: Int32, width: UInt16, height: UInt16, pressed: Bool) -> Data // 32 bytes
    nonisolated static func scroll(x: Int32, y: Int32, width: UInt16, height: UInt16, horizontal: Float, vertical: Float) -> Data // 21 bytes
    nonisolated static func backOrScreenOn(action: UInt8) -> Data           // 2 bytes
    nonisolated static func text(_ string: String) -> Data?                 // tipo 1, tamanho u32, UTF-8; nil se vazio ou acima de 300 bytes
    nonisolated static let collapsePanels = Data([7]), expandNotifications = Data([5])
    enum Action { static let down: UInt8 = 0, up = 1, move = 2 }            // toque e tecla (tecla: down 0, up 1)
    enum Key { static let home: Int32 = 3, back = 4, enter = 66, delete = 67, appSwitch = 187, power = 26 }
}
```

Regras de bytes (big-endian):
- `touch`: `[2][action][pointer u64 = mousePointer][x i32][y i32][w u16][h u16][pressure u16][actionButton i32][buttons i32]`, com pressão `0xFFFF` ao pressionar e `0` ao soltar, `actionButton` 1 em down e up (zero em move), `buttons` 1 enquanto pressionado e 0 ao soltar.
- `scroll`: `[3][x i32][y i32][w u16][h u16][h i16][v i16][buttons i32 = 0]` com cada valor `Int16(clamp(valor / 16, -1, 1) * 32767)`.
- `keycode`: `[0][action][keycode i32][repeat i32 = 0][meta i32]`.

- [ ] **Step 1: Write the failing tests:**

```swift
// H264Tests
func testSplitsNALsWithThreeAndFourByteStartCodes()
func testLengthPrefixedUsesFourByteSizes()           // dois NAL de 3 e 5 bytes → 00 00 00 03 … 00 00 00 05 …
func testParameterSetsFindSPSAndPPS()                // config com SPS (tipo 7), PPS (tipo 8) e um NAL de outro tipo
func testParameterSetsNeedBoth()                     // só SPS → nil
// ScrcpyControlTests
func testKeycodeBytes()                              // HOME down: 00 00 00 00 03 00 00 00 00 00 00 00 00 (14 bytes, ordem exata)
func testTouchDownAndUpBytes()                       // 32 bytes: tipo, ação, id FF×8, x, y, 1080, 2340, pressão FFFF/0000, botões
func testScrollBytesAreClamped()                     // vertical 100 → 0x7FFF; -100 → 0x8001 (−32767); 1 → 2047
func testTextRules()                                 // "olá" ok; "" nil; 301 bytes nil
func testSingleByteMessages()                        // collapsePanels == [7], expandNotifications == [5], backOrScreenOn(0) == [4,0]
```

- [ ] **Step 2: Run** `.superpowers/m --filter 'H264Tests|ScrcpyControlTests'`. Expected: falha de compilação.
- [ ] **Step 3: Implement** os dois arquivos.
- [ ] **Step 4: Run** `.superpowers/m`. Expected: PASS. Commit `feat(mac): H.264 e mensagens de controle do scrcpy`.

---

### Task 3: Conversão de coordenadas e opções do servidor (puras)

**Files:**
- Create: `macOS/Sources/NexusMasterSync/ScrcpyLaunch.swift`
- Test: `macOS/Tests/NexusCoreTests/ScrcpyLaunchTests.swift`

**Interfaces:**
- Produces:

```swift
enum ScrcpyLaunch {
    nonisolated static func socketName(scid: UInt32) -> String                       // "scrcpy_" + 8 hex minúsculos
    nonisolated static func serverArguments(version: String, scid: UInt32, maxSize: Int, maxFPS: Int, bitRate: Int) -> [String]?  // nil se a versão tiver caracteres inválidos
    nonisolated static func serverURL(forScrcpy executable: String) -> URL?          // …/bin/scrcpy → …/share/scrcpy/scrcpy-server
    nonisolated static func devicePoint(viewPoint: CGPoint, viewSize: CGSize, videoSize: CGSize) -> (x: Int32, y: Int32)?   // nil fora do vídeo
}
```

Regras:
- `serverArguments` devolve `["CLASSPATH=/data/local/tmp/scrcpy-server.jar", "app_process", "/", "com.genymobile.scrcpy.Server", version, "scid=<8 hex>", "log_level=info", "tunnel_forward=true", "audio=false", "control=true", "video_codec=h264", "max_size=…", "max_fps=…", "video_bit_rate=…", "clipboard_autosync=false", "cleanup=true"]`. A versão só aceita dígitos e pontos.
- `serverURL`: se o executável é um link para a Cellar, resolve o link e sobe dois níveis; devolve `nil` se o arquivo não existir.
- `devicePoint`: enquadra o vídeo na janela mantendo a proporção (como `scaledToFit`), e converte o ponto para pixels do vídeo, limitando a `0...largura-1` e `0...altura-1`. Fora da área do vídeo, `nil`.

- [ ] **Step 1: Write the failing tests:**

```swift
func testSocketNameIsEightLowercaseHexDigits()    // 0xABCDEF → "scrcpy_00abcdef"
func testServerArgumentsMatchTheProtocol()         // ordem e chaves exatas; versão "5.0.1"; "5.0.1; rm" → nil
func testServerURLFollowsTheInstallLayout()        // diretório temporário com bin/scrcpy e share/scrcpy/scrcpy-server → URL certa; sem o arquivo → nil
func testDevicePointInsideAndOnTheEdges()          // janela 400×400, vídeo 1080×2340: centro → (540,1170); canto do vídeo → dentro dos limites
func testClicksOutsideTheVideoAreIgnored()         // faixas laterais → nil
```

- [ ] **Step 2: Run** `.superpowers/m --filter ScrcpyLaunchTests`. Expected: falha de compilação.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `.superpowers/m`. Expected: PASS. Commit `feat(mac): opções do servidor do scrcpy e conversão de coordenadas`.

---

### Task 4: Cliente do servidor (execução) e teste contra o celular

**Files:**
- Create: `macOS/Sources/NexusMasterSync/ScrcpyClient.swift`
- Test: `macOS/Tests/NexusCoreTests/ScrcpyDeviceTests.swift` (opcional, ligado por `NEXUS_SCRCPY_SERIAL`)

**Interfaces:**
- Consumes: `ScrcpyStreamParser`, `ScrcpyControl`, `ScrcpyLaunch` (Tasks 1 a 3).
- Produces:

```swift
final class ScrcpyClient: @unchecked Sendable {
    init(adb: String, scrcpyExecutable: String)
    var onEvent: (@Sendable (ScrcpyEvent) -> Void)?
    var onEnded: (@Sendable (String?) -> Void)?        // motivo, ou nil se foi pedido
    func start(serial: String) throws                  // bloqueante até conectar; lança com mensagem em português
    func send(_ message: Data)                         // fila serial; ignora se parado
    func stop()                                        // idempotente
}
```

Regras:
- `start`: acha o servidor com `ScrcpyLaunch.serverURL` (erro: "O servidor do scrcpy não foi encontrado. Reinstale o scrcpy."), lê a versão de `scrcpy --version`, faz o `adb push`, escolhe uma porta local livre e um `scid` aleatório, executa `adb forward`, inicia o servidor com `adb shell` e conecta (repetindo por até 8 s) ao túnel duas vezes, lendo o byte de teste na primeira.
- A leitura do vídeo roda numa thread própria e alimenta o `ScrcpyStreamParser`. A leitura do socket de controle só descarta o que o servidor mandar.
- `stop`: fecha os sockets, encerra o processo do servidor, executa `adb forward --remove` e ainda apaga o arquivo do celular, e chama `onEnded(nil)` uma vez.
- Se o processo do servidor terminar ou o vídeo fechar, chama `onEnded(motivo)` uma vez.

- [ ] **Step 1: Write the failing test** `testStartAndStopLeaveNothingBehind` (opcional): com `NEXUS_SCRCPY_SERIAL` definido, inicia o cliente, espera o evento `.session` e um quadro-chave (até 10 s), confere que a largura e a altura são maiores que 100, envia `collapsePanels`, para o cliente e confere que `adb forward --list` não tem mais a porta e que `ps` do celular não tem mais o servidor. Sem a variável, `XCTSkip`.
- [ ] **Step 2: Run** `.superpowers/m --filter ScrcpyDeviceTests`. Expected: falha de compilação.
- [ ] **Step 3: Implement** `ScrcpyClient` conforme as regras.
- [ ] **Step 4: Run** `NEXUS_SCRCPY_SERIAL=192.168.3.31:5555 .superpowers/m --filter ScrcpyDeviceTests`. Expected: PASS contra o celular. Depois `.superpowers/m`. Commit `feat(mac): cliente do servidor do scrcpy`.

---

### Task 5: Tela do celular dentro do app

**Files:**
- Create: `macOS/Sources/NexusMasterSync/PhoneDisplay.swift`
- Modify: `macOS/Sources/NexusMasterSync/ScreenMirror.swift` (nova rota `.inApp`, estado do controle, cliente)
- Modify: `macOS/Sources/NexusMasterSync/Dashboard.swift` (a janelinha usa a tela nova; botões Início e Voltar usam o canal novo; "Controlar" usa a rota)
- Test: `macOS/Tests/NexusCoreTests/PhoneDisplayTests.swift`

**Interfaces:**
- Consumes: Tasks 1 a 4.
- Produces:

```swift
final class H264Presenter {        // converte config + frames em CMSampleBuffer e os enfileira no layer
    init(layer: AVSampleBufferDisplayLayer)
    func handle(_ event: ScrcpyEvent)
}
struct PhoneDisplay: NSViewRepresentable   // desenha o vídeo e converte mouse/roda/teclado em ScrcpyControl
```

- [ ] **Step 1: Write the failing test** `PhoneDisplayTests`:
  - `testPresenterBuildsAFormatFromConfigAndAcceptsFrames` com um SPS/PPS e um quadro reais de 64×64, gerados em memória por um `VTCompressionSession` (se o codificador não estiver disponível no ambiente do teste, `XCTSkip`) e conferindo que o layer fica sem erro (`status != .failed`);
  - `testSessionPacketResetsTheFormat`: depois de um evento `.session` o apresentador descarta o formato anterior.
- [ ] **Step 2: Run** `.superpowers/m --filter PhoneDisplayTests`. Expected: falha de compilação.
- [ ] **Step 3: Implement:**
  - `H264Presenter`: em `.config`, cria o formato com `CMVideoFormatDescriptionCreateFromH264ParameterSets` (tamanho de NAL 4); em `.frame`, converte com `lengthPrefixed`, cria o `CMSampleBuffer` (PTS em microssegundos, sem `DisplayImmediately` desligado: usa `kCMSampleAttachmentKey_DisplayImmediately` e `NotSync` nos quadros não chave) e o enfileira; em `.session`, esvazia o layer e descarta o formato; se o layer entrar em `.failed`, faz `flush`.
  - `PhoneDisplay`: `NSView` com o layer; `mouseDown/Dragged/Up` enviam toque (down, move, up) pelo `devicePoint`; `rightMouseDown` envia `backOrScreenOn`; `scrollWheel` envia rolagem; `keyDown` envia texto, ou Enter e Apagar como teclas; recebe o foco ao clicar.
  - `ScreenMirror`: `controlRoute(hasWirelessADB:scrcpyInstalled:)` ganha o caso `.inApp` (ADB pelo Wi-Fi + o servidor do scrcpy existe); `beginInAppControl(peer:wireless:)` cria o `ScrcpyClient`, liga `onEvent` ao apresentador e a `onEnded` ao estado, e mostra o motivo se falhar; `endInAppControl()` para o cliente. Início e Voltar enviam `keycode` pelo cliente. Se o celular desconectar, encerra.
  - `Dashboard`: a janelinha mostra `PhoneDisplay` quando o controle é dentro do app; "Controlar" usa a nova rota.
- [ ] **Step 4: Run** `.superpowers/m`. Expected: PASS. Commit `feat(mac): controle do celular dentro do app`.

---

### Task 6: Revisão final

- [ ] Revisão da branch por um revisor independente e correção dos achados importantes. Não gerar ZIP até o usuário pedir.
