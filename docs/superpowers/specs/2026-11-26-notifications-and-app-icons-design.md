# Notificações mais úteis e ícones nos apps fixados

Data: 2026-11-26 · Status: aprovado no chat

## Intenção

Usando o app, o dono do produto encontrou três problemas:

1. **Conteúdo escondido.** As notificações chegam ao Mac como "Notificação recebida", sem o texto.
2. **Fechar não funciona.** O ✕ "não fecha", e ele quer que fechar no Mac feche também no celular.
3. **Faltam atalhos.** Ele quer um ícone que feche todas as notificações e quer ver o ícone dos apps do Android fixados no Mac, sem o nome.

## Causas encontradas

- **Conteúdo escondido.** O conteúdo é ocultado em três pontos:
  - "Ocultar conteúdo" no Android, ligado por padrão;
  - "Ocultar conteúdo neste Mac", ligado por padrão;
  - o celular bloqueado. Em `MirrorNotifications.privateContent`, `isDeviceLocked` sempre oculta, mesmo com o Android configurado para mostrar conteúdo na tela de bloqueio (`lock_screen_allow_private_notifications=1` no aparelho dele).
- **✕ sem efeito.** O ✕ funciona: uma notificação de teste saiu do celular. As que "não fecham" são fixas (ONGOING / NO_CLEAR / FOREGROUND_SERVICE), como Spotify, TickTick e depuração USB, e o Android não deixa nenhum app fechá-las. O Mac só desabilita o botão, sem explicar.
- **Apps sem ícone.** `launcherApps` envia apenas `component` e `label`. Um frame tem no máximo 256 KiB, então os ícones de ~200 apps não cabem na lista.

## Design aprovado

### 1. Fechar e limpar (Mac)

- ✕ numa notificação que pode ser fechada: envia `noticeDismiss`, como hoje. Ela sai do Mac quando o Android confirma com `noticeRemoved`.
- ✕ numa notificação fixa:
  - vira **"Ocultar no Mac"**, com o ícone `eye.slash` e a dica "Fixa no Android — ocultar só no Mac";
  - a notificação some do Mac e da Central de Notificações do macOS;
  - ela volta se o título ou o texto mudar, e o Mac esquece o ocultamento quando ela sai do celular.
- Ícone **"Limpar todas"** no topo do painel de notificações (compacto e completo):
  - dispensa no Android todas as notificações do celular selecionado que podem ser fechadas;
  - oculta no Mac as fixas.
- Não muda o protocolo: só usa `noticeDismiss`, que já existe.

### 2. Conteúdo com o celular bloqueado (Android)

O conteúdo é ocultado quando acontece qualquer uma destas condições:

- "Ocultar conteúdo" está ligado;
- a notificação é `VISIBILITY_SECRET`;
- o celular está bloqueado **e** a tela de bloqueio do Android também ocultaria o conteúdo. Isso acontece quando `lock_screen_allow_private_notifications` é 0 e a notificação não é `VISIBILITY_PUBLIC`.

Desbloqueado, nada muda.

### 3. Ícones dos apps fixados

- Nova mensagem Mac → Android: `launcherIconsRequest` com `components` (até 24 itens).
- Resposta: `launcherIcons` com `launcherIcons: [{component, data}]`, onde `data` é um PNG de 48×48 em base64.
- O Android ignora componentes inválidos ou que não sejam do launcher.
- O Mac pede só os ícones dos apps fixados que ainda não estão em cache. O cache fica em disco, nas preferências, por componente.
- Os fixados aparecem como uma fileira de ícones de 32 pt: o nome fica no `.help` e na acessibilidade, e o toque abre o app como hoje.
- Sem ícone (Android antigo, ou antes da resposta chegar), o fixado mostra o nome, como hoje.

### 4. Controlar sem autorização e sem cair ao bloquear (Mac)

- Com o ADB pelo Wi-Fi configurado para o celular selecionado (`wirelessControlDevice(for:)`) e o scrcpy instalado, "Controlar" usa o scrcpy (`launchScrcpy(audioOnly: false, wireless:)`) em vez do espelhamento:
  - nada é pedido no celular;
  - a janela continua aberta com o celular bloqueado e mostra a tela de bloqueio, onde dá para digitar o PIN pelo Mac.
- Abrir um app fixado nesse modo: abre o app pelo ADB (`openApp`) e o scrcpy.
- Sem ADB pelo Wi-Fi ou sem scrcpy, o comportamento continua o de hoje (espelhamento embutido).
- O controle abre numa janela própria do scrcpy. Colocar o vídeo do ADB dentro da janela do app fica fora de escopo.

### 5. Digitalizar abre a câmera direto (Mac + Android)

- Quando o Mac envia `scanRequest` (atalho ⌃⌥⌘D ou outro pedido de digitalização) e há ADB pelo Wi-Fi:
  - o Mac também roda `am start` no `MainActivity` do MasterSync com a extra `accept-scan=<id>`;
  - tenta primeiro o pacote `com.nexus.mastersync` e depois `com.nexus.mastersync.direct`.
- O Android aceita automaticamente o pedido com esse id por até 20 s: abre a câmera simples, sem o aviso "Fotografar para o Mac?", não importa se a extra ou o `scanRequest` chega primeiro.
- Com o celular bloqueado, o Android pede o desbloqueio antes de abrir a câmera. Isso é uma limitação do sistema.
- Sem ADB pelo Wi-Fi, ou se o `am start` falhar, continua o aviso de hoje.

## Não objetivos

- Mudar os padrões de "Ocultar conteúdo".
- Fechar notificações fixas no Android, o que é impossível.
- Ícones na lista completa do popover de apps.

## Antiobjetivos

- Uma notificação fixa ocultada no Mac reaparecer sozinha sem ter mudado.
- O conteúdo aparecer no Mac quando a tela de bloqueio do Android o esconde.
