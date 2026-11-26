# Cartão do player de mídia com saída de áudio

Data: 2026-11-26 · Status: aprovado no chat

## Intenção

O player de música e vídeo do Mac é hoje um painel simples: título, artista e botões. O dono do produto quer um cartão no estilo de um player moderno (capa, dados da faixa, controles e barra de progresso), **translúcido**, com a escolha de onde o som sai: no **celular** ou no **Mac**.

## Como é hoje

- Android → Mac: `mediaStatus` leva só `name` (título), `text` (artista) e `playing`.
- Mac → Android: `mediaCommand` com `message` = `play`, `pause`, `next` ou `previous`.
- O painel "Áudio do Android" tem a chave "Ouvir no Mac" (scrcpy só de áudio pelo ADB), título, artista, 3 botões e o volume do Mac. Os botões Anterior, Reproduzir, Pausar e Próxima aparecem também, soltos, em "Ações no Android".

## Design aprovado

### O cartão

```
┌──────────────────────────────────────────┐
│ ┌──────┐  Título                       ♡  │
│ │ capa │  Artista: …                       │
│ │      │  Álbum: …                         │
│ └──────┘  Ano: …   ·   2 de 14             │
│──────────────────────────────────────────│
│    Saída: [ Celular | Mac ]               │
│        ⏮    ⏸    ⏭    ☰                  │
│  0:56 ━━━━●━━━━━━━━━━━━━━━━━━━━  3:43     │
└──────────────────────────────────────────┘
```

- **Estilo:** o layout acima, com a paleta do app do Mac. O fundo é **translúcido**: material de vidro (`ultraThinMaterial`) com uma leve cor de destaque por cima e borda fina. Com "Reduzir transparência" ligado no macOS, o fundo vira o `surface` sólido.
- **Dados:** cada linha (Artista, Álbum, Ano, "N de M") só aparece quando o app de música informa o dado. "N de M" precisa dos dois números. Só com o número da faixa aparece "Faixa N".
- **Controles:** anterior, play/pause (círculo cheio, maior) e próxima.
- **Barra de progresso:** mostra o tempo decorrido e a duração. Se o app permite pular (`canSeek`), arrastar a barra pula no tempo. Entre uma atualização e outra, o Mac avança o tempo sozinho enquanto está tocando.
- **♡ favoritar:** só aparece se o app de música aceita avaliação do tipo coração. Mostra se a faixa já está favoritada.
- **☰ fila:** só aparece se o app de música expõe uma fila. Abre uma lista com até 30 itens e, ao tocar num, pula para ele.
- **Repetir e aleatório:** ficam de fora. O Android não tem um comando padrão para isso.
- **Saída Celular | Mac:**
  - "Mac" leva o áudio do celular para o Mac (scrcpy só de áudio, como o "Ouvir no Mac" de hoje) e o celular fica em silêncio;
  - "Celular" encerra isso;
  - sem o ADB pelo Wi-Fi configurado, "Mac" abre o guia de configuração;
  - enquanto conecta, mostra um indicador;
  - o volume do Mac aparece só quando a saída é o Mac.
- **Sem mídia ativa:** o cartão mostra "Nada tocando no Android", mantém o seletor de saída e esconde os controles.
- **Android antigo** (sem os campos novos): título, artista e os botões, sem capa nem barra.
- **Onde fica:** o cartão **substitui** o painel "Áudio do Android" e os botões soltos de "Ações no Android". O "Tocar telefone" continua.

### Protocolo (só acréscimos)

- `mediaStatus` ganha, quando conhecidos: `artist`, `albumName`, `year`, `trackNumber`, `trackCount`, `durationMs`, `positionMs` (já avançada até o momento do envio), `speed`, `artKey`, `canSeek`, `canLike`, `liked`, `hasQueue`. Os campos `name`, `text` e `playing` continuam.
- Capa: o Mac pede com `mediaArtRequest { artKey }` quando a chave muda e ainda não tem a imagem. O Android responde com `mediaArt { artKey, mime: "image/jpeg", data }`, um JPEG de até 256 px e 48 KB, só se a chave ainda for a da faixa atual.
- Fila: `mediaQueueRequest` e resposta `mediaQueue { queue: [{id, title}], queueId }`.
- `mediaCommand` ganha `message` = `seek` (com `positionMs`), `like`, `unlike` e `queueItem` (com `queueId`).
- Todos os comandos usam a mesma permissão de hoje (`mediaControl`).

## Não objetivos

- Repetir, aleatório, letras, volume do celular.
- Controlar mais de uma sessão de mídia ao mesmo tempo (vale a primeira ativa, como hoje).

## Antiobjetivos

- A capa de uma faixa aparecer enquanto toca outra.
- A barra passar da duração ou ficar negativa.
- Decodificar a capa travar a tela.
- Perder o volume do Mac ou o "Tocar telefone".
