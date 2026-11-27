# Novo design do Mac: janela de vidro com barra lateral

Data: 2026-11-26 · Status: aprovado (abordagem 2) · Fonte: projeto "MasterSync Android-macOS" no Claude Design, arquivo `MasterSync.dc.html` (protótipo, layout A)

## Intenção

Refazer o visual do app do Mac para seguir o protótipo: uma janela de vidro com barra lateral, acento verde-água e modo claro/escuro. Hoje o app usa paleta quente (marrom e laranja) e navegação por abas no topo.

## Decisões do dono do produto

- **Só o Mac.** O Android fica como está agora.
- **Navegação A (barra lateral).** Sem o layout B de abas flutuantes.
- **Telas que o app não tem** (Chamadas, Webcam, Mensagens SMS/RCS) entram no menu como **"em breve"**, sem funcionalidade.

## Design

### Paleta e vidro
- Troca de `NexusPalette` (arquivo `NexusAppearance.swift`) pelos valores do protótipo: acento verde-água (oklch 0.72 0.15 165, convertido para sRGB), azul secundário, e superfícies translúcidas (painel, linha, realce, trilho).
- Fundo da janela em vidro (`NSVisualEffectView`) com duas manchas de cor desfocadas atrás; cantos de 24 pt.
- Respeita "Reduzir transparência" (superfícies sólidas) e "Reduzir movimento".

### Estrutura da janela
- **Barra lateral (244 pt):** cartão do celular (nome, estado "Conectado · Wi‑Fi", bateria com barra), lista de seções com ícone e contador, e no rodapé o cartão "Área de transferência" com o último texto copiado.
- **Cabeçalho do conteúdo:** título da seção + subtítulo, como no protótipo.
- **Seções existentes, reaproveitando o conteúdo atual:** Visão geral (Celular), Conversa, Galeria, Documentos, Arquivos, Notificações, Controle remoto, Dispositivos, Configurações. A área de transferência sai das abas e vive no cartão da lateral (a seção continua acessível por ele).
- **Apps (novo no protótipo de 26/11 20:54):** tela com apps fixados, todos os apps (busca) e "abertos"; os 5 primeiros fixados aparecem na barra lateral e no menu da barra. Abrir um app usa a janelinha de controle existente; janelas separadas por app ficam de fora.
- **Mini player flutuante (novo no protótipo):** substitui o cartão de mídia da Visão geral; recolhido ou expandido, com saída No Mac / No celular, volume e fila.
- **"Em breve":** Chamadas, Webcam, Mensagens (SMS/RCS), com ícone, texto curto e sem ações.

### Telas
Cada tela passa a usar painéis de vidro com a nova paleta, conforme o protótipo: Visão geral com cartão do aparelho e atalhos rápidos; Conversa com bolhas (minhas em verde-água); Notificações em cartões com fechar; Galeria em grade; Arquivos com progresso; Controle com a janelinha do celular em moldura. A fidelidade visual ao protótipo é a prioridade; o comportamento de cada tela **não muda** (nenhuma função atual pode sumir).

### Tema
- Escuro, claro ou automático, como hoje (`preferredScheme`). Opacidade do vidro fixa em 30%.

## Não objetivos
- Layout B (abas flutuantes), seletor de layout, controle de opacidade do vidro.
- Telas de Chamadas, Webcam e SMS funcionando; barra de menus falsa, dock de demonstração e simulações do protótipo.
- Mudar o Android ou o protocolo.

## Antiobjetivos
- Perder alguma função de hoje (atalhos, arrastar arquivos, controle no app, player, chat).
- Texto ilegível sobre o vidro (contraste mínimo 4,5:1 no claro e no escuro).
- Janela lenta por excesso de desfoque.

## Aviso
Mac e Android ficam com paletas diferentes até o Android receber o mesmo design (você já reclamou disso antes). Isso pode ser feito depois.

## Abordagens consideradas
1. Trocar a casca e a paleta, manter o conteúdo das telas: menor risco, mas a fidelidade ao protótipo é parcial.
2. **Reescrever cada tela fiel ao protótipo (escolhida pelo dono do produto):** layout, espaçamentos, tipografia e componentes iguais ao protótipo, ligados às funções que já existem. Custa mais e exige cuidado para não perder funções (cada função atual precisa continuar acessível).
3. Só trocar as cores: rápido, mas não entrega a barra lateral nem o vidro.
