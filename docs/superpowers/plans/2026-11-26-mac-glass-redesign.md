# Novo design do Mac (janela de vidro) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refazer o visual do app do Mac fiel ao protótipo `MasterSync.dc.html` (janela de vidro, barra lateral, acento verde-água), sem perder nenhuma função atual.

**Architecture:** `NexusPalette` ganha os valores do protótipo (mesmos nomes de propriedade, para o app inteiro mudar de cor de uma vez) e um fundo de vidro nativo (`NSVisualEffectView`). A casca (`DashboardHeader` com abas) é substituída por uma barra lateral; cada tela de `Dashboard.swift` é reescrita no layout do protótipo, ligada aos dados e às ações que já existem. Componentes novos e autocontidos ficam em arquivos próprios; o que usa estado privado do `Dashboard` é reescrito no lugar.

**Tech Stack:** Swift 6, SwiftUI/AppKit, XCTest (`swift test --package-path macOS --scratch-path /private/tmp/claude-501/mac-build`, atalho `.superpowers/m`).

**Spec:** `docs/superpowers/specs/2026-11-26-mac-glass-redesign-design.md`. Protótipo de referência (versão de 26/11 20:54, com Apps e mini player): `docs/superpowers/design/MasterSync.dc.html` (Mac) e `docs/superpowers/design/MasterSync-Android.dc.html` (celular, só referência; não faz parte deste plano). O ZIP `MasterSync Android-macOS-project.zip` na raiz **não** deve ser commitado.

## Global Constraints

- Branch nova `mac-glass-redesign`, criada a partir de `in-app-control` (trabalho empilhado, como as anteriores).
- Só o app do Mac. Android, protocolo e `NexusCore` não mudam.
- Navegação A (barra lateral de 244 pt). Sem layout B, sem seletor de layout, sem controle de opacidade do vidro (fixa em 30%).
- Acento: oklch(0.72 0.15 165) ≈ sRGB `#2FCB9A`-região; o implementador converte e fixa os valores em `NexusPalette` (escuro: acento texto oklch 0.8 0.13 165; claro: oklch 0.5 0.13 165). Texto sobre o acento: `#06130D`.
- Cantos: janela 24, painéis 20, cartões pequenos 14–18, ícone-selo 12.
- O protótipo novo traz **Apps** (fixados, todos os apps, abertos, opções), **apps fixados na barra lateral e no menu** e um **mini player flutuante** (recolhido/expandido, Mac ou celular). Entram nesta versão; "janelas próprias por app" (uma janela do Mac para cada app do celular) **não** entram: abrir um app usa a janelinha de controle que já existe.
- Chamadas, Webcam e "SMS e RCS" entram como **Em breve**: aparecem na barra lateral numa seção "Em breve", abrem uma tela explicativa sem ações.
- Nenhuma função atual pode sumir: atalhos, arrastar arquivos, controle no app, player de mídia, chat, notificações (fechar, limpar todas, responder), scan, ADB Wi‑Fi, configurações de atalhos, onboarding.
- Contraste mínimo 4,5:1 do texto principal e do secundário sobre a janela, nos dois temas. "Reduzir transparência" troca o vidro por cor sólida; "Reduzir movimento" desliga animações de entrada.
- Não gerar ZIP nem instalar APK; só compilar e testar (preferência do usuário).
- Textos em português do Brasil.

## Review Focus

1. Janela pequena (mínimo 780×570): a barra lateral e as telas não podem cortar nem sobrepor conteúdo; telas rolam.
2. Tema claro com vidro: textos secundários continuam legíveis (teste de contraste).
3. "Reduzir transparência" ligado: fundo sólido, sem texto ilegível.
4. Nenhum celular conectado / lista vazia: cada tela mostra um estado vazio, não painéis quebrados.
5. Funções que moram hoje na tela inicial (apps fixados, player, tocar celular, foto com Android, DND, arrastar para enviar) continuam acessíveis: apps na barra lateral e na tela Apps, player no mini player, o resto na Visão geral/Controle.
6. Celular sem a permissão de lista de apps (`launcherAvailable` falso) ou lista ainda carregando: tela Apps mostra estado vazio explicativo, sem travar nem esconder o menu.

---

### Task 1: Branch, paleta e vidro

**Files:**
- Modify: `macOS/Sources/NexusMasterSync/NexusAppearance.swift`
- Create: `macOS/Sources/NexusMasterSync/GlassComponents.swift`
- Test: `macOS/Tests/NexusCoreTests/NexusPaletteTests.swift`

**Interfaces:**
- Produces (em `NexusPalette`, mantendo `canvas, surface, control, border, ink, muted, accent, accentInk, accentSurface, connected` com valores novos) novos tokens: `panel`, `panel2`, `line`, `edge`, `active`, `track`, `input`, `faint` (texto terciário), `secondary` (azul oklch 0.72 0.15 260), `windowTint: Color` (30% de opacidade).
- Produces `static func contrast(_ a: Color, _ b: Color) -> Double` (WCAG) em `NexusPalette`, só para teste/uso interno.
- Produces em `GlassComponents.swift`: `GlassBackground` (NSViewRepresentable, `NSVisualEffectView` material `.underWindowBackground`, blendingMode `.behindWindow`), `View.glassPanel(radius: CGFloat = 20)`, `IconBadge(systemName:size:)` (selo 12 pt com fundo acento 18%), `Avatar(initials:hue:size:)`, `GlassToggle(isOn: Binding<Bool>)` (36×22, bolinha branca), `StatusDot(color:pulsing:)`.
- `NexusBackdrop` passa a usar `GlassBackground` + duas manchas desfocadas (verde-água e azul) quando a transparência não está reduzida; sólido caso contrário.

- [ ] **Step 1:** `git checkout -b mac-glass-redesign` (a partir de `in-app-control`).
- [ ] **Step 2: Testes que falham** em `NexusPaletteTests`: `testInkAndMutedMeetContrastOnWindowInBothSchemes` (ink e muted vs. `canvas` ≥ 4.5 em `.dark` e `.light`), `testAccentInkMeetsContrastOnAccent` (≥ 4.5), `testTokensDifferBetweenSchemes` (panel, line, active diferem entre os esquemas).
- [ ] **Step 3: Rodar** `.superpowers/m --filter NexusPaletteTests`. Expected: falha de compilação/asserção (tokens e `contrast` não existem).
- [ ] **Step 4: Implementar** os tokens e `contrast` em `NexusAppearance.swift` com os valores do bloco `tokens()` do protótipo (escuro/claro) convertidos para sRGB; atualizar `nexusPanel` para usar `panel`/`line`; `NexusPillStyle` passa a usar `accent` novo. Criar `GlassComponents.swift` com os componentes acima.
- [ ] **Step 5: Rodar** a suíte inteira (`.superpowers/m`). Expected: 0 falhas. Compilar e abrir não é necessário ainda.
- [ ] **Step 6: Commit** `feat(mac): paleta de vidro e componentes base`.

### Task 2: Modelo de navegação (seções e "em breve")

**Files:**
- Modify: `macOS/Sources/NexusMasterSync/NexusModel.swift` (enum `Section`, linhas ~6–40)
- Create: `macOS/Sources/NexusMasterSync/SidebarItems.swift`
- Test: `macOS/Tests/NexusCoreTests/SidebarItemsTests.swift`

**Interfaces:**
- `Section` ganha `case apps = "Apps", calls = "Chamadas", sms = "SMS e RCS", webcam = "Webcam"`, `var isComingSoon: Bool`, `var subtitle: String` (textos do protótipo, ex.: Conversa → "Conversa e arquivos com o celular"; Notificações → "Espelhadas em tempo real"; Galeria → "Fotos e vídeos do celular"; Arquivos → "Enviados e recebidos"; Controle remoto → "Controle o celular pelo Mac") e ícones SF Symbols para as novas.
- `struct SidebarItem: Identifiable { section: Section; badge: Int? }` e `enum SidebarGroup { main, soon, footer }`; `func sidebarItems(group:badges:) -> [SidebarItem]` onde `badges: [Section: Int]` (notificações pendentes, arquivos não vistos).
- Ordem `main`: overview, conversation, notifications, gallery, documents, files, remote, apps. `soon`: calls, sms, webcam. `footer`: devices, settings. `clipboard` não aparece na lista (acessível pelo cartão da lateral).

- [ ] **Step 1: Testes que falham:** `testMainGroupOrder` (inclui `apps` por último), `testComingSoonSectionsAreOnlyInSoonGroup`, `testClipboardIsNotListed`, `testBadgeOnlyWhenPositive` (badge 0 → nil), `testEverySectionHasTitleAndSubtitle` (todas as `Section.allCases`).
- [ ] **Step 2: Rodar** `.superpowers/m --filter SidebarItemsTests`. Expected: FAIL (tipos não existem).
- [ ] **Step 3: Implementar** o enum estendido e `sidebarItems`. Corrigir os `switch` exaustivos em `Dashboard.swift`/`DashboardChrome.swift` com `case .calls, .sms, .webcam: EmptyView()` provisório.
- [ ] **Step 4: Rodar** suíte. Expected: 0 falhas.
- [ ] **Step 5: Commit** `feat(mac): seções em breve e itens da barra lateral`.

### Task 3: Casca da janela (barra lateral + cabeçalho)

**Files:**
- Create: `macOS/Sources/NexusMasterSync/Sidebar.swift`
- Modify: `macOS/Sources/NexusMasterSync/Dashboard.swift` (`body`, linhas ~46–120; `dashboardContent`), `macOS/Sources/NexusMasterSync/DashboardChrome.swift` (remove `DashboardHeader`; mantém `ConnectionBar` até a Task 9), `macOS/Sources/NexusMasterSync/NexusApp.swift` (`frame(minWidth: 780…)`, `defaultSize(width: 1240, height: 790)`)
- Test: `macOS/Tests/NexusCoreTests/ShellRenderTests.swift`

**Interfaces:**
- Consumes: `sidebarItems(group:badges:)`, `NexusPalette` novos tokens, `IconBadge`, `StatusDot`, `GlassToggle`.
- Produces `struct Sidebar: View { @ObservedObject var model: NexusModel }`: espaço de 28 pt no topo para os botões da janela; cartão do celular (miniatura do aparelho, nome, "Conectado · Wi‑Fi"/"Desconectado", barra de bateria com % e "carregando"); lista `main`; seção "Em breve" (itens esmaecidos); rodapé: cartão "Área de transferência" (último texto copiado + origem; clique abre `.clipboard`) e itens `footer`.
- Cabeçalho do conteúdo: altura 58, título 20 pt/700 + subtítulo 12,5 pt secundário, à direita o botão de notificações atual e a busca da galeria (quando `model.section == .gallery && gallery.advanced`).

- [ ] **Step 1: Teste que falha** `ShellRenderTests.testSidebarRendersInBothSchemes` (padrão de `MediaPlayerCardRenderTests`: `ImageRenderer` a 244×764, esquema claro e escuro, imagem não nula com o tamanho pedido) e `testSidebarWithoutPhoneShowsDisconnected` (renderiza sem celular selecionado sem travar).
- [ ] **Step 2: Rodar** `--filter ShellRenderTests`. Expected: FAIL (`Sidebar` não existe).
- [ ] **Step 3: Implementar** `Sidebar` e trocar o `VStack` de `Dashboard.body` por `HStack { Sidebar; conteúdo }` sobre o fundo de vidro; remover `DashboardHeader` e `SectionGroup`; manter `ConnectionBar` abaixo do conteúdo. Trocar o título grande de cada tela pelo cabeçalho novo.
- [ ] **Step 4: Rodar** suíte e `swift build`. Expected: 0 falhas, build limpo.
- [ ] **Step 5: Commit** `feat(mac): barra lateral e cabeçalho do novo design`.

### Task 4: Visão geral

**Files:**
- Modify: `macOS/Sources/NexusMasterSync/Dashboard.swift` (`overview(size:)` ~215–290, `compactNotifications`, `androidLauncher`, `audioPanel`)
- Test: `macOS/Tests/NexusCoreTests/ShellRenderTests.swift`

**Interfaces:**
- Consumes: componentes da Task 1, `Sidebar`/cabeçalho da Task 3.
- Layout do protótipo (grade `290 | 1fr | 1fr`): cartão do aparelho à esquerda (nome, "Conectado via Wi‑Fi", bateria 44 pt com barra, linhas Rede / Armazenamento / Não perturbar com os dados reais disponíveis em `model.selectedStatus`; o que não existir é omitido, não inventado); quatro atalhos rápidos (Controlar → `.remote`, Enviar arquivo → `.files`, Foto com o Android → `model.requestInstantPhoto()`, Tocar celular → `model.findPhone()`); cartão Notificações (3 últimas + "Ver todas"); cartão Conversa (últimas mensagens + "Abrir"); cartão Galeria recente (7 miniaturas reais de `model.received`/galeria; vazio se não houver) ; cartão Área de transferência (texto atual + botão "Colar no Mac"/"Copiado ✓" com a ação atual de copiar).
- Funções que viviam na tela inicial e **precisam continuar acessíveis**: alerta de bateria, DND (`androidDndToggle`) e botão "Conectar Android" ficam como cartão extra na Visão geral; apps fixados vão para a barra lateral e para a tela Apps (Task 9); o player vai para o mini player flutuante (Task 10).

- [ ] **Step 1: Teste que falha** `ShellRenderTests.testOverviewRendersConnectedAndDisconnected` (renderiza `Dashboard` com `NexusModel` de teste nos dois estados, 1240×764, sem travar, imagem do tamanho certo).
- [ ] **Step 2: Rodar.** Expected: FAIL ou imagem em branco/tamanho errado antes da mudança (registrar a saída).
- [ ] **Step 3: Implementar** `overview` conforme acima, reaproveitando as views privadas existentes dentro de cartões `glassPanel`.
- [ ] **Step 4: Rodar** suíte. Expected: 0 falhas.
- [ ] **Step 5: Commit** `feat(mac): nova visão geral`.

### Task 5: Conversa

**Files:**
- Modify: `macOS/Sources/NexusMasterSync/Dashboard.swift` (`conversationPanel` ~643, `conversationBubble` ~725)
- Test: `macOS/Tests/NexusCoreTests/ShellRenderTests.swift`

**Interfaces:**
- Layout "Mensagens" do protótipo: coluna esquerda de 280 pt com busca e a lista de aparelhos pareados (avatar, nome, última mensagem, hora, bolinha de não lida) e painel direito com cabeçalho (avatar, nome, "Enviado pelo <aparelho>"), bolhas (minhas em acento com texto `#06130D`, recebidas em `panel2`, raio 18, largura máx. 62%), separador "Hoje", campo arredondado e botão circular de enviar. Mídia, links e nome do aparelho remetente (já existentes em `conversationBubble`/`ChatMedia`) são preservados.
- Sem botão de ligar (não há função).

- [ ] **Step 1: Teste que falha** `testConversationRendersWithAndWithoutMessages`.
- [ ] **Step 2: Rodar.** Expected: FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar** suíte. Expected: 0 falhas.
- [ ] **Step 5: Commit** `feat(mac): nova tela de conversa`.

### Task 6: Notificações

**Files:**
- Modify: `macOS/Sources/NexusMasterSync/Dashboard.swift` (`notifications` ~1030, `compactNotifications` ~800, `notificationFeedback`, `dismissNoticeButton`, `clearAllNoticesButton`)
- Test: `macOS/Tests/NexusCoreTests/ShellRenderTests.swift`

**Interfaces:**
- Layout do protótipo: coluna de cartões (ícone do app 38 pt, app + hora, título, corpo completo, botão fechar 28 pt) e coluna direita de 300 pt "Espelhar notificações de" com um `GlassToggle` por app **se** `NotificationSync` já tiver filtro por app; se não tiver, a coluna mostra os controles que existem (espelhar, "Limpar todas", DND). Responder (`replyNotice`) e o ícone real do app (`LauncherIcons`) são preservados; estado vazio "Tudo em dia."

- [ ] **Step 1: Teste que falha** `testNotificationsRenderEmptyAndPopulated`.
- [ ] **Step 2: Rodar.** Expected: FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar** suíte. Expected: 0 falhas.
- [ ] **Step 5: Commit** `feat(mac): nova tela de notificações`.

### Task 7: Galeria, Documentos e Arquivos

**Files:**
- Modify: `macOS/Sources/NexusMasterSync/Dashboard.swift` (`gallery` ~987, `documents` ~961, `files` ~1007, `receivedGallery`, `fileRow`, `ReceivedTile` ~1615), `GalleryBrowser.swift` (somente estilo)
- Test: `macOS/Tests/NexusCoreTests/ShellRenderTests.swift`

**Interfaces:**
- Galeria: barra "Clique para selecionar · arraste para o Finder" + botão "Salvar N no Mac"; grade de 6 colunas, miniaturas com raio 14, anel de acento e selo de check na seleção (seleção múltipla nova só se já houver ação de salvar; senão manter o comportamento atual e só restilizar). Filtros avançados e agrupamento por data (`LibraryDatePicker`) preservados.
- Documentos: mesma grade/lista com as ações de digitalização (`Digitalizar novo`, copiar, apagar) em botões do novo estilo.
- Arquivos: zona de soltar tracejada de 190 pt ("Arraste arquivos aqui para enviar ao <aparelho>", "ou clique para escolher · salvos em Downloads/MasterSync") e lista de transferências com ícone de direção, nome, tamanho e barra de progresso de 4 pt; `fileImporter`, `dropDestination` e a fila (`FileDropQueue`) preservados.

- [ ] **Step 1: Teste que falha** `testLibraryScreensRender` (galeria, documentos e arquivos vazios e com itens de teste).
- [ ] **Step 2: Rodar.** Expected: FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar** suíte. Expected: 0 falhas.
- [ ] **Step 5: Commit** `feat(mac): novas telas de galeria, documentos e arquivos`.

### Task 8: Controle remoto (janelinha do celular)

**Files:**
- Modify: `macOS/Sources/NexusMasterSync/Dashboard.swift` (`remote` ~1085, `remotePhonePreview`, `phonePanel`, `embeddedPhone`, `embeddedControlButton`)
- Test: `macOS/Tests/NexusCoreTests/ShellRenderTests.swift`

**Interfaces:**
- Layout "Espelhar tela" do protótipo: à esquerda, painel com o aparelho em moldura (292×600, raio 44, borda escura) contendo `embeddedPhone` (vídeo do controle no app / espelhamento / estado "Tela pronta" com botão "Controlar"); à direita (300 pt): cartão de estado (ponto pulsante, "Controle ao vivo"/"Pronto", texto de ajuda, botão iniciar/parar), grade 3×2 de ferramentas (Início, Voltar, Tocar celular, Enviar arquivo, Controle em janela separada, Áudio) ligadas às ações atuais, cartão com resolução/rota (no app, scrcpy ou compartilhamento). `dropDestination` de arquivos sobre a moldura e o botão de apps fixados preservados.
- A tela `phonePanel` deixa de aparecer na Visão geral (Task 4 já aponta para cá pelo atalho "Controlar").

- [ ] **Step 1: Teste que falha** `testRemoteScreenRendersIdleAndInAppControl` (estado ocioso e `inAppControl` simulado).
- [ ] **Step 2: Rodar.** Expected: FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar** suíte. Expected: 0 falhas.
- [ ] **Step 5: Commit** `feat(mac): nova tela de controle remoto`.

### Task 9: Tela Apps

**Files:**
- Create: `macOS/Sources/NexusMasterSync/AppsScreen.swift`, `macOS/Sources/NexusMasterSync/AppsCatalog.swift`
- Modify: `macOS/Sources/NexusMasterSync/Dashboard.swift` (switch de seções; `androidLauncher`, `launcherPopover`, `pinnedAppButton`, `setPinned`, `launcherPins` passam a alimentar a nova tela e a barra lateral; o popover antigo "Apps do Android" some)
- Test: `macOS/Tests/NexusCoreTests/AppsCatalogTests.swift`, `macOS/Tests/NexusCoreTests/ShellRenderTests.swift`

**Interfaces:**
- Produces `enum AppsCatalog` (puro, testável): `static func filter(_ apps: [AndroidApp], query: String) -> [AndroidApp]` (ignora acentos e caixa, casa por nome visível), `static func pinned(_ apps: [AndroidApp], ids: [String]) -> [AndroidApp]` (mantém a ordem dos ids e ignora ids que não existem mais), `static func toggled(_ ids: [String], id: String) -> [String]` (fixa no fim ou remove), `static func sidebarPins(_ apps: [AndroidApp]) -> [AndroidApp]` (os 5 primeiros).
- Layout do protótipo (grade `1fr | 300`): cartão **Fixados** (ícones 50 pt com nome, botão de fechar para desafixar, texto "Os 5 primeiros ficam na barra lateral e no menu", vazio: "Use o alfinete num app abaixo para fixá-lo aqui."); cartão **Todos os apps · N** com busca "Buscar apps do <celular>" e grade de 4 colunas (ícone real de `model.launcherIcons`, nome, categoria ou "Aberto no Mac", botão de alfinete); coluna direita com **Abertos no Mac** (o app em controle agora, se houver, com "Trazer para frente" = foca a janelinha e "Fechar" = `screen.endAll()`; vazio: "Nenhum app aberto. Clique num app para abri-lo numa janela própria." ajustado para "…para abri-lo no controle do celular.") e **opções** só com o que existe de verdade (nenhuma opção inventada: "Usar com o celular bloqueado" é informativa e sempre ligada pelo controle no app; omitir as demais).
- Abrir um app chama `model.launchAndroidApp(_:)` (rota inApp/scrcpy/mirror já decidida lá) e leva para `.remote`. Pins continuam em `@AppStorage("android-launcher-pins")` por celular (mesmo formato de hoje), então nada se perde.

- [ ] **Step 1: Testes que falham** `AppsCatalogTests`: `testFilterIgnoresAccentsAndCase` ("camera" acha "Câmera"), `testFilterEmptyQueryReturnsAll`, `testPinnedKeepsIdOrderAndDropsMissing`, `testToggledAddsAtEndAndRemoves`, `testSidebarPinsAreFirstFive`. Em `ShellRenderTests`: `testAppsScreenRendersEmptyAndWithApps`.
- [ ] **Step 2: Rodar** `.superpowers/m --filter AppsCatalogTests`. Expected: FAIL (`AppsCatalog` não existe).
- [ ] **Step 3: Implementar** `AppsCatalog` e `AppsScreen`; ligar a grade de pins da barra lateral (Task 3) a `AppsCatalog.sidebarPins`.
- [ ] **Step 4: Rodar** suíte. Expected: 0 falhas.
- [ ] **Step 5: Commit** `feat(mac): tela de apps e apps fixados na barra lateral`.

### Task 10: Mini player flutuante

**Files:**
- Create: `macOS/Sources/NexusMasterSync/MiniPlayer.swift`
- Modify: `macOS/Sources/NexusMasterSync/Dashboard.swift` (`audioPanel` ~409–480 deixa de estar na Visão geral; overlay no canto inferior direito da janela), `macOS/Sources/NexusMasterSync/MediaPlayerCard.swift` (reuso de peças), `macOS/Sources/NexusMasterSync/MediaPlayerState.swift` (somente se faltar algo)
- Test: `macOS/Tests/NexusCoreTests/MiniPlayerTests.swift`, `macOS/Tests/NexusCoreTests/MediaPlayerCardRenderTests.swift`

**Interfaces:**
- Consumes: `MediaPlayerState`, `MediaOutput`, `model.currentMediaState`, `model.mediaControl`, `model.mediaSeek(toFraction:)`, `model.mediaQueue`, `model.mediaPlay(queueItem:)`, `model.mediaArt`, a escolha de saída que já existe em `audioPanel` (`onOutput`, volume do Mac).
- Produces `enum MiniPlayerView: Equatable { case hidden, mini, full }` e `struct MiniPlayerPresentation` (puro): `static func initial(hasMedia: Bool) -> MiniPlayerView` (`hidden` sem mídia, `mini` com mídia), `static func after(_ view: MiniPlayerView, hasMedia: Bool, userClosed: Bool) -> MiniPlayerView` (mídia some → `hidden`; fechado pelo usuário continua `hidden` até a faixa mudar).
- `struct MiniPlayer: View`: 360 pt, canto inferior direito (24 pt de margem). **Recolhido:** capa 44, título, artista com ícone da saída (laptop_mac/phone_android), play/pausa, próxima, expandir, barra fina de progresso. **Expandido:** app + aparelho, recolher/fechar, capa 96 (ou área de vídeo com "Abrir em janela" só se houver vídeo real; se não houver, não mostrar), título/artista, barra de posição com `seek` (só se `canSeek`), voltar 10 s/anterior/play/próxima/avançar 10 s (só os comandos que `MediaCommands` suporta; os outros somem), volume do Mac quando a saída é Mac, seletor **Som do celular: No Mac | No celular** (a mesma lógica de hoje, inclusive o guia quando falta ADB sem fio), lista "Mídia no celular" (fila real, se `hasQueue`).
- Aparece em qualquer tela; não cobre o botão de enviar do chat (margem inferior extra na Conversa).

- [ ] **Step 1: Testes que falham** `MiniPlayerTests`: `testNoMediaIsHidden`, `testMediaStartsMini`, `testClosedStaysHiddenUntilTrackChanges`, `testMediaDisappearingHides`. Em `MediaPlayerCardRenderTests`: `testMiniPlayerRendersCollapsedAndExpanded` (claro e escuro).
- [ ] **Step 2: Rodar** `.superpowers/m --filter MiniPlayerTests`. Expected: FAIL.
- [ ] **Step 3: Implementar** `MiniPlayerPresentation` e `MiniPlayer`, e mover a lógica de `audioPanel` para ela; a Visão geral perde o cartão de mídia.
- [ ] **Step 4: Rodar** suíte. Expected: 0 falhas.
- [ ] **Step 5: Commit** `feat(mac): mini player flutuante`.

### Task 11: Dispositivos, Configurações, Área de transferência e onboarding

**Files:**
- Modify: `macOS/Sources/NexusMasterSync/Dashboard.swift` (`devices` ~847, `clipboard` ~901, `settings` ~1198, `appearanceOption`, `connectionOnboarding`, `wirelessOnboarding`, `pairing`, `card(_:icon:content:)` ~1536), `DashboardChrome.swift` (`ConnectionBar`), `ShortcutRecorder.swift`, `WirelessClipboardSetup.swift`, `MediaPlayerCard.swift` (somente tokens de cor)
- Test: `macOS/Tests/NexusCoreTests/ShellRenderTests.swift`

**Interfaces:**
- `card(_:icon:content:)` passa a usar `glassPanel` e `IconBadge`; linhas de ajuste com rótulo, subtítulo e `GlassToggle`, separadas por `line`, como o cartão de opções da Webcam do protótipo. Seção Atalhos, aparência, rede, pareamento, revogar, guia de conexão (sheets) preservados e restilizados; `ConnectionBar` vira faixa de vidro.

- [ ] **Step 1: Teste que falha** `testSettingsDevicesAndClipboardRender`.
- [ ] **Step 2: Rodar.** Expected: FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar** suíte. Expected: 0 falhas.
- [ ] **Step 5: Commit** `feat(mac): novo visual de dispositivos, configurações e área de transferência`.

### Task 12: Telas "Em breve" e menu da barra

**Files:**
- Create: `macOS/Sources/NexusMasterSync/ComingSoonView.swift`
- Modify: `macOS/Sources/NexusMasterSync/Dashboard.swift` (switch de seções), `macOS/Sources/NexusMasterSync/NexusApp.swift` (`MenuBarExtra`, linhas ~66–100)
- Test: `macOS/Tests/NexusCoreTests/ShellRenderTests.swift`

**Interfaces:**
- `struct ComingSoonView: View { let section: Section }`: ícone grande em selo, título, uma frase do que virá (Chamadas: "Atenda e faça ligações pelo Mac."; SMS e RCS: "Leia e responda mensagens do celular no Mac."; Webcam: "Use a câmera do celular como webcam no Mac."), etiqueta "Em breve", sem botões.
- Menu da barra: popover do protótipo (cartão do celular com bateria, grade 2×2 de blocos Área de transferência / Notificações / Espelhar / Controlar ligados aos interruptores reais, fileira "Apps fixados" (5 ícones, abre o app; link "Todos" abre `.apps`), bloco "Copiado no celular", botões "Enviar arquivo…" e "Abrir MasterSync"), mantendo os itens atuais (encerrar controle, parar espelhamento, sessão do scrcpy, encerrar app).

- [ ] **Step 1: Teste que falha** `testComingSoonRendersForEverySoonSection` (as três seções) e `testMenuBarContentRendersWithoutPhone`.
- [ ] **Step 2: Rodar.** Expected: FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar** suíte completa. Expected: 0 falhas.
- [ ] **Step 5: Commit** `feat(mac): telas em breve e novo menu da barra`.

### Task 13: Acabamento, acessibilidade e verificação final

**Files:**
- Modify: arquivos das tarefas anteriores conforme os achados; `docs/superpowers/plans/…` (ledger)
- Test: suíte completa

- [ ] **Step 1:** Varredura: `grep` por cores literais antigas (`0xF3BB7D`, `0x8A4925`, laranja/marrom) e por `.orange`/`.brown` fora da paleta; trocar pelos tokens.
- [ ] **Step 2:** Acessibilidade: rótulos nos botões só com ícone (fechar, enviar, abrir), `accessibilityAddTraits(.isSelected)` na seção atual da barra lateral, ordem de leitura lateral → cabeçalho → conteúdo; `reduceMotion` desliga `msFade`/pulso.
- [ ] **Step 3:** Rodar `swift build -c release` e a suíte completa. Expected: build limpo, 0 falhas.
- [ ] **Step 4:** Revisão final da branch inteira por um revisor (opus) contra a spec e o Review Focus; uma passada de correções (cada uma com teste RED→GREEN).
- [ ] **Step 5: Commit** `fix(mac): acabamento do novo design`.
