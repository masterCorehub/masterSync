# Sistema de design

## macOS

| Papel | Escuro | Claro |
| --- | --- | --- |
| Fundo | `#191412` | `#F5EEE6` |
| Superfície | `#2F2521` | `#FFF9F2` |
| Controle | `#392E28` | `#ECE0D3` |
| Texto | `#F5ECE3` | `#281C16` |
| Texto secundário | `#C4B1A3` | `#635046` |
| Seleção e ação | `#F3BB7D` | `#8A4925` |

A janela usa formas arredondadas, SF e SF Rounded. O fundo escuro quente e a iluminação suave nas bordas se estendem até a barra de título. O âmbar marca a seleção, o atalho principal e as ações de conexão. O tema claro usa a mesma escala em cores de fundo mais claras, com texto escuro.

```text
┌─────────────────────────────────────────────────────────┐
│ Nexus        Início   Biblioteca   Conexão    Busca  ••• │
│ Visão geral   Área de transferência                     │
│                                                         │
│ Visão geral                                             │
│ Galeria     Área de transferência    Documentos Arquivos│
│ Fotos recentes             Documentos recentes          │
│ Últimos itens copiados     Atividade                    │
│                                                         │
│ Android  Estado   Bateria        Transferência    Ação  │
└─────────────────────────────────────────────────────────┘
```

A navegação fixa mantém as páginas do grupo visíveis. Cada grupo lembra a última página aberta durante a sessão. A busca abre seções do Nexus e, na galeria conectada, filtra a mídia pelo nome. A barra inferior reúne estado do Android, bateria, progresso e a ação disponível para a conexão. Seus dados vêm da sessão ativa.

Botões têm nomes acessíveis, o texto acompanha os indicadores de cor e as transições de hover respeitam a redução de movimento. A preferência de redução de transparência desativa a iluminação do fundo.

## Android

O Android usa Material 3 com Roboto, fundos `#F4F6FA` e `#10131B` e destaques em `#454EC4` e `#AAB0FF`. O cartão do início usa a forma de um monitor para indicar o Mac conectado. A navegação inferior e a barra de estado adaptam-se à aparência selecionada.
