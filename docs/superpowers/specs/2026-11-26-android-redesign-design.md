# Reformulação do design do app Android

Data: 2026-11-26 · Status: rascunho para aprovação

## Intenção

O app Android do MasterSync está difícil de usar e não combina com o app do Mac:

- **Recursos misturados e difíceis de achar.** Cada aba guarda uma parte das coisas. Para ativar um recurso, é preciso explorar o app. A aba Conversa junta chat, área de transferência, arquivos, arquivos recebidos e teclado. As Configurações misturam permissões do Android com as chaves dos recursos. O botão "Manter conexão em segundo plano" aparece em quatro lugares.
- **Não fica claro o que ativar.** Um recurso depende de três coisas: a chave no Android, a ativação no Mac e as permissões do sistema. O app não mostra essas três coisas juntas.
- **Visual feio e diferente do Mac.** O Android usa índigo frio. O Mac usa uma paleta quente (creme e caramelo), botões em pílula e verde para "conectado".

Uso real, segundo o dono do produto: o celular funciona principalmente como **ponte para o Mac**. Nele, a pessoa **conecta e libera as permissões** que os recursos do Mac precisam. Dentro do app Android, o que mais se usa é a **Conversa** e o **envio de arquivos**.

## Objetivos

1. Uma tela inicial mostra todos os recursos e o estado de cada um.
2. Cada recurso informa, num lugar só, o que falta para funcionar (Android, Mac e conexão), com o botão que resolve cada passo.
3. Identidade visual igual à do Mac: mesma paleta nos temas claro e escuro, botões em pílula, painéis arredondados e verde para "conectado".
4. Mensagens e arquivos ficam juntos numa conversa única.
5. Menos texto explicativo. O estado e os passos explicam o recurso.

## Não objetivos

- Mudar protocolo, serviços, `LocalClient` ou o comportamento dos recursos. A única mudança de dados permitida está em "Dados para a Conversa".
- Adotar Navigation Compose ou ViewModels por tela.
- Mexer no app do Mac.
- Usar cores dinâmicas do Android (Material You).

## Antiobjetivos (seria um fracasso mesmo funcionando)

- Algum recurso ou opção que existe hoje ficar inacessível ou mais difícil de achar.
- A conexão, os pedidos do Mac (digitalização, foto, espelhamento) ou o compartilhamento vindo de outro app pararem de funcionar.
- O app ficar com outra cara que ainda não lembre o Mac.
- Uma opção existir em dois lugares diferentes. Cada configuração mora num lugar só.

## Restrições

- Kotlin, Jetpack Compose, Material 3 (BOM 2025.10.01). Android 10 ou superior.
- Duas edições: `full` e `direct`. `BuildConfig.NOTIFICATION_RELAY` é falso na `direct`. Nessa edição, Notificações e Controle de mídia não aparecem.
- Pontos de entrada que precisam continuar funcionando: `ACTION_SEND` (arquivo compartilhado de outro app), os extras `open-share` (Bloco de Configurações rápidas `NexusTile` e `RequestNotifications`) e `open-scan` (`RequestNotifications`), além da aba salva em `onSaveInstanceState`.
- Diálogos atuais de pedidos do Mac (espelhar tela, foto, digitalização) e de texto reconhecido (OCR) continuam com o mesmo comportamento.
- O app inteiro segue em português do Brasil.

## Abordagens consideradas

1. **Refazer só a camada de telas, organizada por partes (escolhida).** Tema próprio, componentes, quatro telas e um catálogo de recursos que calcula estado e passos. Serviços e controlador não mudam. A reformulação visual e de organização é completa, com risco baixo para a conexão.
2. **Refazer telas e arquitetura** (Navigation Compose, ViewModel por tela). Mexe na ligação com serviços e no controlador sem benefício perceptível para 3 abas e um painel. Descartada.
3. **Só trocar o visual no arquivo único.** Resolve o "feio", mas não a organização nem o "o que ativar". Descartada.

O dono do produto escolheu a 1.

## Design decidido com o dono do produto

### Navegação: 3 abas

| Aba | Conteúdo |
| --- | --- |
| **Início** | Cartão do Mac conectado e lista "Recursos para o Mac" |
| **Conversa** | Linha do tempo de mensagens e arquivos com o Mac conectado |
| **Conexão** | Macs pareados, Ler QR, conexão em segundo plano, aparência |

A engrenagem e a tela "Permissões e acessos" deixam de existir. O conteúdo delas foi redistribuído (veja a tabela de mapeamento).

### Início (layout "A · Painel de recursos")

- **Cartão do Mac** em destaque (`accentSurface`): selo verde "Conectado" ou estado atual, nome do Mac e "Rede local • em segundo plano" quando a conexão em segundo plano está ativa. Ao tocar, vai para a aba Conexão. Sem Mac pareado, o cartão vira o convite para parear, com o botão "Ler QR".
- **Painel "Recursos para o Mac"**: uma linha por recurso, com nome e selo de estado.
  - Verde **Ativo**: tudo pronto.
  - Caramelo **com o primeiro passo pendente** em poucas palavras, como "Permitir fotos", "Dar acesso" ou "Ligar no Mac".
  - Cinza **Desligado**: a chave do Android está desligada.
- Ao tocar numa linha, abre o painel do recurso.

### Painel do recurso (painel deslizante por cima do Início)

Usa `ModalBottomSheet` do Material 3. Estrutura:

1. **Cabeçalho:** nome do recurso, uma frase sobre o que ele faz e a chave principal (liga e desliga no Android).
2. **"Para funcionar":** lista numerada dos requisitos, em ordem. Requisito cumprido aparece com ✓ verde. Requisito pendente aparece com número, descrição curta e pílula de ação ("Abrir", "Permitir", "Ligar"). Só aparecem os requisitos que valem para aquele recurso.
3. **"Opções":** configurações específicas do recurso. Listas longas, como os apps de Notificações, abrem um segundo nível dentro do painel.

### Conversa

- Linha do tempo única com o Mac conectado: mensagens (balões) e arquivos enviados e recebidos (cartões com nome, tamanho e ação "Salvar" nos recebidos). Tudo em ordem cronológica.
- Barra de escrita fixa embaixo: botão "＋" (anexar arquivo), campo "Mensagem para o Mac" e botão enviar.
- Transferências em andamento aparecem como cartão com barra de progresso na própria linha do tempo.
- Um arquivo vindo de `ACTION_SEND` aparece como cartão "Pronto para enviar" acima da barra de escrita, com "Enviar ao Mac" e "Cancelar".
- Se faltar algo para o chat ou para os arquivos (Mac desconectado, Arquivos desligado), aparece um aviso curto no topo com o atalho para o painel do recurso correspondente.

#### Dados para a Conversa (decidido pelo dono do produto: opção "a")

Hoje as três fontes não permitem uma ordem única: `ChatEntry` (NexusApplication.kt) não tem horário, `TransferQueue.Sent` não tem horário nem tamanho, e `Received` é montado a partir dos arquivos em disco (com data de modificação). Mudança mínima aprovada:

- `ChatEntry` ganha `time: Long` (epoch ms), gravado na criação. Na leitura do JSON, campo ausente vira `0`.
- `TransferQueue.Sent` ganha `time: Long` e `size: Long`. Na leitura, campo ausente vira `0`.
- `Received` usa a data de modificação do arquivo que já existe.
- A linha do tempo junta as três fontes e ordena por horário. Itens com horário `0` (histórico antigo) vão para o topo, na ordem original da lista de cada um.
- Sem mudança no protocolo com o Mac, nos limites de histórico (400 / 150) nem no formato além desses campos opcionais. Os testes unitários cobrem a leitura de entradas antigas sem os campos.

### Identidade visual

- Paleta copiada de `macOS/Sources/NexusMasterSync/NexusAppearance.swift` (claro / escuro):

  | Papel | Claro | Escuro |
  | --- | --- | --- |
  | canvas | F5EEE6 | 191412 |
  | surface | FFF9F2 | 2F2521 |
  | control | ECE0D3 | 392E28 |
  | border | DED0C2 | 59453B |
  | ink | 281C16 | F5ECE3 |
  | muted | 635046 | C4B1A3 |
  | accent | 8A4925 | F3BB7D |
  | accentInk | FFF8F0 | 27180F |
  | accentSurface | F2E0CB | 473225 |
  | connected | 386342 | A6CD9E |

- O fundo tem o brilho radial suave do `NexusBackdrop` do Mac no canto superior direito. Ele fica desligado quando o sistema pede menos transparência ou animações reduzidas.
- Botões em pílula: o principal é preenchido com `accent`, o secundário usa `control`. Painéis com raio de cerca de 19 dp e borda `border` a 65%. O destacado usa `accentSurface` com borda `accent` a 50%.
- Tema: Automático, Claro ou Escuro (a opção atual `options.theme` continua igual).

## Catálogo de recursos e mapeamento do que existe hoje

| Recurso | Chave principal | "Para funcionar" | Opções |
| --- | --- | --- | --- |
| Área de transferência | `clipboard` | Ligado no Mac (`permission.clipboard`); conexão em segundo plano (recomendado, para receber do Mac com outro app aberto) | Teclado Nexus: ativar / escolher teclado (opcional); aviso "Atualize o app do Mac para imagens" quando `!clipboardImages` |
| Arquivos | `files` | Ligado no Mac (`permission.files`) | — |
| Galeria | `gallery` (ligar chama `requestGallery`) | Permissão de fotos e vídeos (total ou parcial no Android 14+); ligado no Mac (`permission.gallery`); conexão em segundo plano (para tela bloqueada) | Revisar fotos e vídeos; Enviar novas fotos e vídeos (`syncNewMedia`) |
| Notificações *(só full)* | `notificationMirror` | Acesso às notificações; ligado no Mac (`permission.notifications`); notificações do app permitidas | Ocultar conteúdo; Controle do Não Perturbe; Controle de mídia (`mediaControl`); lista de apps (`blockedApps`, segundo nível) |
| Espelhar tela | `mirror` | Notificações do app permitidas; conexão em segundo plano | — (a autorização do sistema acontece a cada sessão, então basta uma linha informativa) |
| Digitalizar e câmera | `remoteScan` ("Aceitar pedidos do Mac": cobre digitalização, foto instantânea e scanPaste) | Câmera; Arquivos ligado no Android e no Mac | Enviar páginas e PDF automaticamente (`autoScan`); Fotografar documento e Recortar e digitalizar várias páginas (com o aviso do Google Play Services), sempre disponíveis, mesmo com o recurso desligado; Digitalizações (segundo nível: lista de documentos com Salvar PDF, Ler texto, Enviar PDF e exportar páginas em JPG/PNG) |
| Localizar celular | `findPhone` | Notificações do app permitidas | — |

| Hoje | Depois |
| --- | --- |
| Aba Digitalizar | Painel Digitalizar (ações + Digitalizações) |
| Aba Conversa: chat, arquivos, recebidos | Aba Conversa (linha do tempo única) |
| Aba Conversa: Área de transferência automática + teclado | Painel Área de transferência |
| Aba Dispositivos | Aba Conexão |
| Configurações → Aparência | Aba Conexão |
| Configurações → Notificações / Galeria / Espelhamento / Ações remotas | Painéis dos recursos correspondentes |
| Permissões e acessos → câmera | Passo do painel Digitalizar e ação "Ler QR" (pede na hora) |
| Permissões e acessos → demais | Passos dos painéis que dependem de cada permissão |
| "Manter conexão em segundo plano" (4 lugares) | Aba Conexão + passo nos painéis que dependem dela |

### Regras de estado (escolhas do Claude, a revisar na leitura)

- **Digitalizar:** a chave principal é `remoteScan`, porque é ela que decide o que o Mac pode pedir. `autoScan` é uma opção.
- **Mac desconectado:** as permissões do lado do Mac voltam a falso quando a conexão cai (NexusApplication.kt). Por isso, sem Mac conectado, os passos "Ligado no Mac" aparecem em cinza ("Confirme quando o Mac conectar") e não contam como pendência. O selo do recurso no Início reflete só o lado do Android. O cartão do Mac no topo mostra a desconexão.
- **Passo "Ligar no Mac":** não tem pílula de ação, porque não dá para resolver pelo celular. O texto diz onde ativar no Mac (por exemplo "No Mac: Celular → Área de transferência").
- Estados de um recurso: `Desligado` (chave do Android desligada), `Pendente(primeiro passo)` e `Ativo`. Um passo pode estar `Feito`, `Pendente` ou `Aguardando Mac`.
- Avisos globais (mensagem de feedback e "Sua tela está sendo compartilhada / Parar") ficam como faixa no topo de qualquer aba, como hoje. O aviso do chat leva à aba Conexão quando o Mac está desconectado, ou ao painel Arquivos quando o problema é Arquivos.

Pontos de entrada: `open-share` e `ACTION_SEND` abrem a aba Conversa. `open-scan` abre o Início com o painel Digitalizar aberto.

## Estrutura de código (decisão do construtor, aprovada pela abordagem 1)

- `ui/theme/`: `NexusTheme` (paleta → `ColorScheme` do Material 3 + tokens extras, como `connected`, `accentSurface` e `border`, via `CompositionLocal`), fundo com brilho, formas.
- `ui/components/`: pílula, painel, selo de estado, linha de passo, linha de chave.
- `ui/features/`: modelo do catálogo (`Feature`, `Requirement`, estado), uma função pura que monta a lista a partir de `Options`, `Permissions`, estado da conexão e permissões do sistema, com testes unitários.
- `ui/home/`, `ui/sheet/`, `ui/conversation/`, `ui/connection/`: as telas.
- `ui/NexusScreen.kt`: só o `Scaffold`, as abas, o roteamento e os diálogos de pedido do Mac.
- `MainActivity`: as cerca de 24 funções viram um objeto `NexusActions` (interface ou data class de lambdas). O `enum Tab` passa a ter `Home`, `Conversation` e `Connection`. A restauração de aba salva tolera nomes antigos e cai no Início.

## Deixado para o construtor

- Ícones de cada recurso e das abas (Material Icons core, ou o conjunto extended se fizer falta).
- Textos exatos dos selos e dos passos, desde que curtos e no tom do app do Mac.
- Animações e transições, respeitando as animações reduzidas.
- Como a linha do tempo da Conversa ordena itens sem horário (as mensagens hoje não têm data). A regra mais simples é manter a ordem de chegada.
