# Imagens na Conversa, links clicáveis e quem enviou

Data: 2026-11-26 · Status: aprovado no chat

## Intenção

Ao usar "Enviar ao Android" no Mac, o dono do produto quer que a Conversa mostre exatamente o que foi enviado, como numa conversa comum: se for uma imagem, a imagem aparece na Conversa. Ele também quer ver, em cada item, qual dispositivo enviou.

## Como é hoje

- Texto e links enviados pelo Mac chegam como mensagem de Conversa, com o texto como foi enviado.
- Arquivos e imagens chegam como um **cartão**: nome e tamanho no Android (com "Salvar"), ícone de documento e nome no Mac. Nenhum dos dois mostra a imagem.
- Nenhum item diz quem enviou. Só o lado do balão e a cor distinguem.
- Nomes dos aparelhos que já existem: o Mac anuncia `Host.current().localizedName` e o Android anuncia `Build.MODEL`.

## Design aprovado

### 1. Imagens na Conversa

- **Android:** um arquivo recebido com mime `image/jpeg`, `image/png`, `image/webp`, `image/gif`, `image/heic` ou `image/heif` aparece como a **própria imagem** num balão, com "Salvar" abaixo. O arquivo original continua inteiro e é ele que "Salvar" guarda.
  - A imagem é decodificada reduzida (maior lado perto de 1080 px) e fora da thread principal.
  - Se não for possível decodificar, ou se o arquivo passar de 50 MB, mostra o cartão de hoje.
  - Enquanto a transferência não termina, aparece a barra de progresso, como hoje.
- **Mac:** imagens enviadas ou recebidas aparecem como miniatura (maior lado 280 pt) no lugar do ícone de documento. O clique abre a prévia, como hoje.
- Outros arquivos continuam como cartão.

### 2. Links clicáveis (Android)

URLs `http://` e `https://` no texto de uma mensagem viram links que abrem no navegador. A pontuação final (`.,;:!?)`) não entra no link.

### 3. Quem enviou

- Cada balão, cartão e imagem, nos dois apps, mostra uma linha pequena acima do conteúdo:
  - o **nome do aparelho que enviou**, com o horário depois quando o item tem horário. Exemplo: `Galaxy S23+ · 14:32`;
  - itens de histórico antigo sem horário mostram só o nome.
- Mensagens e arquivos enviados por este aparelho mostram o nome **deste** aparelho. Os do outro mostram o nome do outro.
  - No Android: este aparelho é `Build.MODEL` e o outro é o nome do Mac conectado.
  - No Mac: este aparelho é `Host.current().localizedName` e o outro é o nome do celular selecionado.
- Nome vazio cai em "Este celular" / "Este Mac" para o próprio aparelho, e em "Mac" / "Celular" para o outro.

## Não objetivos

- Imagem enviada **pelo Android** aparecer na Conversa do Android (o app apaga o arquivo temporário depois de enviar).
- Prévia de vídeo ou de PDF.
- Mudar o protocolo com o outro aparelho.

## Antiobjetivos

- Uma foto grande travar a tela ou estourar a memória.
- A imagem sumir da Conversa sem deixar o cartão de volta quando a decodificação falha.
- O "Salvar" entregar a versão reduzida em vez do original.
