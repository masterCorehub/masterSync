# O ADB acompanha o celular entre redes: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ao trocar de rede, a sincronização da área de transferência pelo Wi-Fi acha o celular sozinha, sem digitar IP nem usar o cabo (e com o cabo, repara o ADB sozinha).

**Architecture:** O `LocalServer` expõe o IPv4 de cada celular conectado. Funções puras decidem o novo endereço e o próximo passo da recuperação. O laço de `ADBClipboard.startWiFi` usa essas funções a cada tentativa.

**Tech Stack:** Swift (NexusCore + NexusMasterSync), XCTest.

**Spec:** `docs/superpowers/specs/2026-11-26-adb-follows-network-design.md`

## Global Constraints

- Só IPv4. Uma tentativa de conexão a cada 3 s, como hoje.
- O `deviceID` continua sendo conferido antes de aceitar um endereço novo.
- Textos em português do Brasil, exatamente os da seção "Mensagens" do spec.
- Nenhuma compilação em release nem instalação no aparelho neste plano: só testes e checagem de compilação.
- Verificação: `.superpowers/m`.

## Review Focus

1. Um IPv4 embutido em IPv6 (`::ffff:192.168.3.31`) vira `192.168.3.31`, e um IPv6 de verdade, nome de host ou nada vira `nil`. Teste `testIPv4FromEndpoint`.
2. Endereço guardado com IPv6, sem porta ou inválido não gera endereço novo. Teste `testRebasedAddressRejectsUnusableInput`.
3. O mesmo IP do guardado não gera endereço "novo". Teste `testRebasedAddressIgnoresTheSameHost`.
4. Um aparelho não autorizado ou offline no USB não é usado no reparo. Teste `testUSBSerialsKeepsOnlyAuthorizedDevices`.
5. Número de porta ou serial inválidos nunca chegam a um comando. Teste `testTCPIPArgumentsAreValidated`.

---

### Task 1: IP de cada celular no LocalServer

**Files:**
- Modify: `macOS/Sources/NexusCore/FramedConnection.swift` (`var remoteHost: String?`)
- Modify: `macOS/Sources/NexusCore/LocalServer.swift` (`establish` guarda, o fechamento apaga; `public func host(of peerID: String) -> String?`)
- Test: `macOS/Tests/NexusCoreTests/PeerHostTests.swift`

**Interfaces:**
- Produces: `FramedConnection.ipv4(from endpoint: NWEndpoint?) -> String?` (estática, interna ao módulo) e `LocalServer.host(of:) -> String?`.

- [ ] **Step 1: Write the failing test** `testIPv4FromEndpoint`:
  - `.hostPort(host: .ipv4(192.168.3.31), port: 1)` → `"192.168.3.31"`;
  - `.hostPort(host: .ipv6(::ffff:192.168.3.31), …)` → `"192.168.3.31"`;
  - `.ipv6(fe80::1)` → `nil`;
  - `.hostPort(host: .name("celular.local", nil), …)` → `nil`;
  - `nil` → `nil`.
- [ ] **Step 2: Run** `.superpowers/m --filter PeerHostTests`. Expected: falha de compilação.
- [ ] **Step 3: Implement.** `remoteHost` usa `socket.currentPath?.remoteEndpoint ?? socket.endpoint`. O servidor guarda `peerHosts[peer.id]` em `establish` e o remove quando o celular desconecta.
- [ ] **Step 4: Run** `.superpowers/m`. Expected: PASS. Commit `feat(mac): o servidor sabe o IP de cada celular`.

---

### Task 2: Funções puras de endereço e recuperação

**Files:**
- Create: `macOS/Sources/NexusMasterSync/ADBAddress.swift`
- Test: `macOS/Tests/NexusCoreTests/ADBAddressTests.swift`

**Interfaces:**
- Produces:

```swift
enum ADBAddress {
    nonisolated static func rebased(_ saved: String?, onto host: String?) -> String?     // "IP:porta" com o host novo, ou nil
    nonisolated static func usbSerials(from devicesOutput: String) -> [String]           // só "device", sem ":" no serial
    nonisolated static func port(of address: String?) -> Int?
}
enum ADBRecovery {
    enum Step: Equatable { case retry(status: String), repairOverUSB(status: String), waitForCable(status: String) }
    nonisolated static func next(failures: Int, usbDeviceAttached: Bool) -> Step
}
extension ADBClipboardSession {
    nonisolated static func tcpipArguments(serial: String, port: Int) -> [String]?       // ["-s", serial, "tcpip", "5555"]
}
```

Regras:
- `rebased`: `saved` precisa ser um `IPv4:porta` válido (`ADBEndpoint`) e `host` um IPv4; se o host for igual ao guardado, devolve `nil`; senão `"\(host):\(porta)"`.
- `usbSerials`: linhas `serial<tab>device ...` do `adb devices`, ignorando serial com `:`, estados `offline` e `unauthorized`, e a linha de cabeçalho.
- `next`: `failures <= 1` → `retry("Procurando o celular nesta rede…")`; `failures >= 2` com cabo → `repairOverUSB("Reativando o ADB do celular pelo cabo…")`; `failures >= 2` sem cabo → `waitForCable("Não achei o ADB do celular nesta rede. Conecte o cabo uma vez: o Mac reativa sozinho.")`.
- `tcpipArguments`: serial só com letras, números, `.`, `_` e `-`; porta de 1024 a 65535; senão `nil`.

- [ ] **Step 1: Write the failing tests:**

```swift
func testRebasedAddressMovesTheHostAndKeepsThePort()   // ("192.168.0.235:5555", "192.168.3.31") → "192.168.3.31:5555"
func testRebasedAddressIgnoresTheSameHost()            // mesmo host → nil
func testRebasedAddressRejectsUnusableInput()          // saved nil/"lixo"/"[::1]:5555"/"1.2.3.4" (sem porta); host nil/"fe80::1"/"celular" → nil
func testUSBSerialsKeepsOnlyAuthorizedDevices()        // saída real de adb devices -l com cabeçalho, USB device, rede offline, unauthorized → só os USB "device"
func testRecoverySteps()                               // (0,false)/(1,true) → retry; (2,true) → repairOverUSB; (2,false)/(5,false) → waitForCable
func testTCPIPArgumentsAreValidated()                  // ("RQCW308WKPA", 5555) ok; serial "a b"/"x;y" → nil; porta 80 / 70000 → nil
```

- [ ] **Step 2: Run** `.superpowers/m --filter ADBAddressTests`. Expected: falha de compilação.
- [ ] **Step 3: Implement** as três funções e `tcpipArguments`.
- [ ] **Step 4: Run** `.superpowers/m`. Expected: PASS. Commit `feat(mac): regras de endereço e recuperação do ADB pelo Wi-Fi`.

---

### Task 3: O laço da sincronização acompanha o celular

**Files:**
- Modify: `macOS/Sources/NexusMasterSync/ADBClipboard.swift` (`startWiFi`; `ADBClipboardSession.usbSerial(matching:)` e `enableTCPIP(serial:port:)`)
- Modify: `macOS/Sources/NexusMasterSync/NexusModel.swift` (define `adbClipboard.addressProvider` perto do `onEnded`)

**Interfaces:**
- Consumes: `LocalServer.host(of:)` (Task 1) e `ADBAddress` / `ADBRecovery` (Task 2).
- Produces: `ADBClipboard.addressProvider: ((ADBWirelessDevice) -> String?)?`.

- [ ] **Step 1: Implement:**
  - `NexusModel` define `adbClipboard.addressProvider = { device in ADBAddress.rebased(device.address, onto: device.peerID.flatMap { server?.host(of: $0) }) }`.
  - Em `startWiFi`, no começo de cada volta do laço: `if let fresh = await self?.freshAddress(for: target) { target.address = fresh }`, onde `freshAddress` roda no MainActor e chama o `addressProvider`.
  - Falhas: um contador `failures` que zera quando a sessão fica pronta. Em vez de `if !wasReady || Task.isCancelled { throw error }`, use `if (!wasReady && target.deviceID == nil) || Task.isCancelled { throw error }`.
  - A cada falha chame `ADBRecovery.next(failures:usbDeviceAttached:)`, onde `usbDeviceAttached` vem de `session.usbSerial(matching: target.deviceID)`:
    - `retry` e `waitForCable` só atualizam o status;
    - `repairOverUSB` roda `session.enableTCPIP(serial:port:)` com a porta guardada ou 5555, espera 2 s, ajusta `target.address` para `host:porta` com o host atual e tenta de novo (no máximo uma vez a cada 3 falhas).
  - `usbSerial(matching:)` roda `adb devices` e usa `ADBAddress.usbSerials`; `enableTCPIP` usa `tcpipArguments`.
- [ ] **Step 2: Run** `.superpowers/m`. Expected: PASS e compila. Commit `feat(mac): a sincronização pelo Wi-Fi acompanha o celular entre redes`.

---

### Task 4: Revisão final

- [ ] Revisão da branch por um revisor independente e correção dos achados importantes. Não gerar ZIP até o usuário pedir.
