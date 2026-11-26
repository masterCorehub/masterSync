# Controle do celular dentro do app, sem autorização

Data: 2026-11-26 · Status: aprovado no chat (opção 2)

## Intenção

O botão "Controlar" tem hoje dois caminhos, e nenhum atende por completo:

- **Janelinha do celular dentro do app:** usa o compartilhamento de tela do Android. Pede autorização no celular a cada sessão e **encerra quando o celular bloqueia**.
- **Janela do scrcpy:** não pede nada e sobrevive ao bloqueio, mas abre numa **janela separada**.

O dono do produto quer a janelinha **dentro do app**, **sem autorização** e **sem cair ao bloquear**.

## Design aprovado

O Mac passa a falar direto com o servidor do scrcpy (o arquivo `scrcpy-server`, que o próprio scrcpy instalado já traz) pelo ADB do Wi-Fi, e mostra o vídeo na janelinha do app.

### Conexão

1. Envia o servidor ao celular (`adb push` para `/data/local/tmp/scrcpy-server.jar`).
2. Abre um túnel local (`adb forward tcp:<porta> localabstract:scrcpy_<scid>`), com um `scid` aleatório de 8 dígitos hexadecimais.
3. Inicia o servidor: `adb shell CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server <versão> scid=<scid> log_level=info tunnel_forward=true audio=false control=true video_codec=h264 max_size=1600 max_fps=60 video_bit_rate=8000000 clipboard_autosync=false cleanup=true`.
   - A versão é a do scrcpy instalado (`scrcpy --version`) e o arquivo vem de `<prefixo do scrcpy>/share/scrcpy/scrcpy-server`.
4. Conecta ao túnel duas vezes, nesta ordem: **vídeo** e depois **controle**. O servidor ainda pode estar subindo, então a conexão é repetida por até 8 s, lendo o byte de teste.
5. Ao parar, fecha os dois sockets, encerra o servidor e remove o túnel.

### Fluxo de vídeo (v5.0.1)

`[0x00]` byte de teste, `[64 bytes]` nome do aparelho, `[4 bytes]` código do codec (`h264`), depois, repetidos, 12 bytes de cabeçalho seguidos do conteúdo:

- primeiro bit 1: **pacote de sessão** (largura e altura de 4 bytes cada, em big-endian). Vem no início e a cada rotação da tela;
- senão, **pacote de mídia**: 8 bytes com o bit 62 (configuração: SPS e PPS), o bit 61 (quadro-chave) e o PTS, e 4 bytes com o tamanho.

O Mac junta SPS e PPS, converte cada quadro de Annex B para o formato com tamanho (4 bytes) e o entrega a um `AVSampleBufferDisplayLayer`, que decodifica por hardware.

### Entrada

Mensagens binárias no socket de controle (todas em big-endian), com os formatos do scrcpy 5.0.1: tecla, texto, toque (32 bytes), rolagem (21 bytes), "voltar ou acordar a tela" e abrir ou fechar o painel de notificações.

- **Clique e arraste** viram um toque contínuo: pressionar, mover e soltar.
- **Roda do mouse ou dois dedos** viram rolagem.
- **Botão direito** é "Voltar" e acorda o celular se a tela estiver apagada.
- **Teclado:** letras e símbolos viram texto; Enter e Apagar viram teclas.
- Os botões que já existem (Início e Voltar) usam o mesmo canal.
- As coordenadas do clique são convertidas respeitando o enquadramento do vídeo na janelinha.

### Integração

- A rota do "Controlar" passa a ter três opções, escolhidas nesta ordem:
  1. **Dentro do app**, quando há ADB pelo Wi-Fi e o servidor do scrcpy existe;
  2. **janela do scrcpy**, quando só o scrcpy existe;
  3. **compartilhamento de tela do Android**, como hoje.
- Se a conexão dentro do app falhar, o botão mostra o motivo e **não** cai sozinho para outra rota.
- O botão "Controlar Android" (janela do scrcpy, com áudio) continua existindo.
- Sem áudio dentro do app. Para ouvir no Mac enquanto controla, a saída "Mac" do player continua valendo.

## Não objetivos

- Áudio dentro da janelinha.
- Copiar e colar entre os aparelhos pela janelinha, e arrastar arquivos para ela.
- Gravar a tela.
- Segunda tela virtual (`new_display`).

## Antiobjetivos

- Travar o app ao receber o vídeo (a leitura roda fora da thread principal).
- Deixar o servidor ou o túnel pendurados no celular ou no Mac depois de parar.
- Um clique cair numa posição errada por causa da faixa preta do enquadramento.
- Rotação da tela deixar a imagem esticada ou congelada.
