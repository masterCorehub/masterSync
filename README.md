# Nexus masterSync

Aplicativos nativos para integrar Android e macOS pela rede local. O Mac usa SwiftUI e AppKit. O Android usa Kotlin, Jetpack Compose e Material 3. Ambos mantêm a sessão criptografada entre os dispositivos pareados.

## Instalar os builds locais

- **macOS 14 ou superior.** Extraia `dist/Nexus masterSync macOS.zip` e abra `Nexus masterSync.app`. O ZIP gerado nesta máquina contém um binário Apple Silicon com assinatura local ad hoc.
- **Android 10 ou superior.** Para instalar pelo gerenciador de arquivos, use `dist/Nexus-masterSync-android-direto.apk`. O pacote assinado aparece como **Nexus masterSync Direto**. Para testar a edição completa, use o [compartilhamento interno do Google Play](https://support.google.com/googleplay/android-developer/answer/9844679?hl=pt-BR) com `dist/Nexus-masterSync-android-debug.apk`.

No Mac, abra **Dispositivos → Ativar rede local → Gerar QR**. No Android, abra **Dispositivos → Ler QR**. Confira o nome e o modelo do celular no Mac e toque em **Autorizar**. Em seguida, habilite a integração desejada nos dois aplicativos. Para usar a conexão enquanto outro aplicativo Android está em foco, habilite **Manter conexão em segundo plano**. O Android mostra uma notificação com a ação **Parar**.

### Copiar e colar texto e imagens

Ative **Sincronizar texto e imagens** em **Área de transferência** no Mac e no painel **Área de transferência automática** no Android. Com o teclado de sua preferência, copie no Android e abra o Nexus. O app envia o conteúdo assim que está em foco e conectado. Você também pode abrir o Nexus pelo atalho das Configurações rápidas. Do Mac para o Android, mantenha a conexão em segundo plano para receber conteúdo enquanto usa outro app. Depois, cole pelo comando de sempre.

#### Sincronizar do Android para o Mac pelo USB

Conecte um único celular, ative a depuração USB e autorize o Mac no aviso do Android. Com o ADB instalado no Mac, abra **Área de transferência → Ativar sincronização USB** no Nexus. Enquanto a sessão estiver ativa, texto e imagens novas entram automaticamente na área de transferência do Mac, com o teclado de sua preferência e com o Nexus fechado no celular. Use **Parar sincronização USB** ou desconecte o cabo para terminar a sessão. O leitor usa a permissão que o Android atribui à sessão ADB e ignora as cópias marcadas como sensíveis. A imagem deve ser oferecida pelo app de origem na área de transferência e ter até 8 MiB.

#### Sincronizar do Android para o Mac pelo Wi-Fi

Com o ADB instalado no Mac e os dois aparelhos na mesma rede, ative **Opções do desenvolvedor → Depuração sem fio** no Android 11 ou superior. No Nexus do Mac, escolha **Área de transferência → Configurar Wi-Fi**. No celular, abra **Parear dispositivo com código** e informe no Mac o endereço dessa janela e o código de seis dígitos. Se a rede bloquear a descoberta automática, informe também o IP e a porta da tela principal da Depuração sem fio. Os endereços usam portas diferentes.

Ao ativar, novas cópias de texto e imagens seguem para o Mac com o Nexus fechado no Android e com o teclado atual. O Mac lembra o aparelho, tenta reconectar enquanto a sessão estiver ativa e descarta o código de pareamento. Se o Android mudar o endereço e a descoberta automática estiver indisponível, atualize o endereço em **Configurar Wi-Fi**. O Android precisa manter a Depuração sem fio ativa. [Depuração sem fio do Android](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi)

### Biblioteca por data e galeria com a tela bloqueada

Ative a galeria no Mac e em **Configurações → Galeria** no Android. Na mesma tela do Android, toque em **Manter conexão em segundo plano**. No Mac, filtre por nome, álbum, tipo ou período de adição. Fotos abrem como prévia sem transferir o original. Vídeos baixam e abrem no visualizador do macOS com **Arquivos** ativado nos dois dispositivos.

Em **Biblioteca**, escolha **Agrupar por → Dia** ou **Mês**. A galeria remota usa a data em que a mídia foi adicionada no Android. Documentos e arquivos já salvos usam a data em que chegaram ao Mac. A galeria também permite uma lista única ordenada pelo nome.

A galeria fica disponível com a tela bloqueada após o primeiro desbloqueio desde a última reinicialização. Em Doze, o Android pode suspender a rede e a galeria volta a responder quando a conexão retorna. [Armazenamento após o desbloqueio](https://developer.android.com/privacy-and-security/direct-boot) · [Modo Doze](https://developer.android.com/training/monitoring-device-state/doze-standby)

### Digitalizar para o Mac

Com **Arquivos** ativo nos dois aparelhos, habilite **Digitalizar → Enviar páginas e PDF ao Mac automaticamente** no Android. Use **Fotografar documento** e confirme a foto na câmera. O Nexus conserva o JPEG, gera o PDF e envia a imagem primeiro. Se quiser recortar, aplicar filtros ou reunir várias páginas, use **Recortar e digitalizar várias páginas** e conclua no scanner avançado. Digitalizações solicitadas pelo Mac e autorizadas no celular já têm um destino. No Mac, **Biblioteca → Documentos** mostra automaticamente a última página recebida assim que ela é verificada e salva.

## Compilar

### macOS

Instale o Xcode com o SDK do macOS e selecione o toolchain. Para empacotar o leitor USB, use também JDK 17 ou 21 e aponte `ANDROID_HOME` para o Android SDK com Platform 36 e Build Tools 36.0.0. Execute na raiz do projeto:

```bash
./scripts/build-macos.sh
swift test --package-path macOS
```

O script entrega o ZIP em `dist`. `NEXUS_CONFIGURATION=debug` produz um build de depuração. `NEXUS_SIGN_IDENTITY` aceita uma identidade de assinatura já configurada no Mac. O script verifica a assinatura local. Notarização, assinatura Developer ID e revisão da loja integram o fluxo de publicação.

### Android

Use JDK 17 ou 21, Android SDK Platform 36, Android SDK Build Tools 36.0.0 e, para instalar pelo terminal, Platform Tools. Aponte `ANDROID_HOME` para o SDK ou defina `sdk.dir` em `android/local.properties`. O Wrapper fixa Gradle 8.13 e verifica o SHA-256 da distribuição.

```bash
cd android
./gradlew :app:assembleFullDebug :app:assembleDirectRelease :app:testFullDebugUnitTest :app:testDirectDebugUnitTest
```

O APK completo de depuração fica em `android/app/build/outputs/apk/full/debug/app-full-debug.apk`. O APK da edição direta sai em `android/app/build/outputs/apk/direct/release/app-direct-release-unsigned.apk` e precisa de assinatura via `apksigner`. Use a mesma chave para instalar futuras atualizações desse pacote. O Android Studio pode abrir a pasta `android` diretamente.

## O que está disponível

As duas edições Android se comunicam com o mesmo app macOS. O quadro descreve a edição completa. O espelhamento de notificações de outros apps e o controle remoto de mídia estão disponíveis na edição completa. A edição direta mantém notificações próprias do Nexus para conexões, scanner e espelhamento de tela.

| Fase | Recursos |
| --- | --- |
| 1 · Fundação | Pareamento por QR com confirmação, descoberta Bonjour, TLS 1.3 com certificado conferido por impressão digital, reconexão, revogação, registro de múltiplos celulares no Mac, bateria e estado de carregamento. O Android guarda vários Macs e mantém uma sessão selecionada por vez. |
| 2 · Integração básica | Texto e links nos dois sentidos, histórico opcional no Mac com fixação e exclusão, opt-out do próximo item, arquivos originais em blocos com SHA-256 e retomada após queda da rede, notificações com filtros, ocultação, Não Perturbe e ações de resposta e dispensa quando oferecidas pelo Android. |
| 3 · Documentos e mídia | Scanner multipágina com recorte, perspectiva e filtros pelo ML Kit, OCR latino, exportação em PDF, JPG e PNG, envio manual de PDF e envio automático de JPEGs e PDF com prévia no Mac. A galeria consulta álbuns, tipos e datas, mostra miniaturas e baixa a mídia original. A sincronização opcional de novas mídias acompanha as autorizações de galeria e arquivos dos dois lados. |
| 4 · Tela e USB | Espelhamento consentido com MediaProjection, redimensionamento, janela e tela cheia no Mac. O modo nativo usa JPEG por TLS com resolução de até 960 px no lado maior e até 15 quadros por segundo. O controle de mouse, teclado, gestos e arraste por USB abre o scrcpy em uma janela própria. |
| 5 · Integrações | Menu de bateria no Mac, atalhos editáveis com Shift + Command, histórico recente de atividade, Quick Settings, Compartilhar no Android, folha de compartilhamento e arraste a partir do Nexus no macOS, controle de mídia e localização por toque mediante autorização. |

### Limites da entrega

- **Área de transferência.** O Android 10 em diante permite a leitura a partir do app em foco ou do teclado padrão. O Teclado Nexus é uma opção para enviar cópias ao Mac enquanto outro app está em foco. Os itens marcados como sensíveis são ignorados. Sincronização de imagens aceita até 8 MiB e depende de os apps envolvidos oferecerem cópia e colagem de imagens. O histórico persistente do Mac guarda texto quando habilitado. [Restrições da área de transferência](https://developer.android.com/about/versions/10/privacy/changes#clipboard-data)
- **Arquivos e galeria.** A retomada pressupõe que o app remetente continue aberto ou conectado em segundo plano. Ela cobre interrupção de transporte. Original de vídeo abre automaticamente após download e verificação. A fila automática de mídia processa até 20 itens por consulta. Os arquivos originais são transferidos sem recodificação. [Acesso parcial à mídia](https://developer.android.com/about/versions/14/changes/partial-photo-video-access)
- **Scanner.** A primeira abertura pode precisar baixar o componente do scanner pelo Google Play Services. ML Kit processa documentos e OCR no dispositivo. O SDK pode enviar métricas de uso e desempenho ao Google durante o uso. [Scanner do ML Kit](https://developers.google.com/ml-kit/vision/doc-scanner/android) · [Termos e privacidade do ML Kit](https://developers.google.com/ml-kit/terms)
- **Espelhamento e controle.** O Android pede consentimento por sessão e a taxa real depende do tamanho dos quadros e da rede. O modo nativo oferece visualização. A janela externa do scrcpy fornece a entrada via USB. Webcam como dispositivo de câmera do macOS, controle nativo por Wi-Fi e extensão de entrada do menu Compartilhar do macOS permanecem em desenvolvimento. [MediaProjection](https://developer.android.com/media/grow/media-projection) · [Controle do scrcpy](https://github.com/Genymobile/scrcpy/blob/master/doc/control.md) · [Extensões de câmera do macOS](https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o)

### Conexão alternativa por USB

Com o Android conectado por cabo, ative a depuração USB e confirme a autorização do Mac no próprio Android. Mantenha apenas o aparelho de teste conectado ou use `adb -s SERIAL`.

```bash
adb -d reverse tcp:47525 tcp:47525
```

O comando acima usa a porta padrão. Se ela estiver ocupada, o Nexus seleciona outra porta e mostra o comando atualizado em **Dispositivos**. Depois de configurar o encaminhamento, use **Gerar QR para USB**. O pareamento segue o mesmo fluxo e as mesmas verificações do Wi-Fi. Para encerrar o encaminhamento, use `adb -d reverse --remove tcp:47525` com a porta que você usou. Para controlar o Android, instale o scrcpy e o ADB e abra **Controle remoto → Abrir controle USB**. [Android Debug Bridge](https://developer.android.com/tools/adb) · [scrcpy oficial](https://github.com/Genymobile/scrcpy)

## Testar a conexão entre plataformas

Inicie um emulador Android e selecione o serial que começa por `emulator-`. O teste usa o aplicativo Kotlin real, a implementação Swift do servidor e a conexão TLS pelo túnel local do emulador. A autorização no Mac é exercitada independentemente pelo teste de loopback.

```bash
cd android
./gradlew :app:assembleFullDebug :app:assembleFullDebugAndroidTest
adb -s emulator-5554 install -r app/build/outputs/apk/full/debug/app-full-debug.apk
adb -s emulator-5554 install -r app/build/outputs/apk/androidTest/full/debug/app-full-debug-androidTest.apk
cd ..
NEXUS_TEST_ANDROID_ADB="$(command -v adb)" NEXUS_TEST_ANDROID_SERIAL=emulator-5554 \
  swift test --package-path macOS
```

O teste troca texto nos dois sentidos, interrompe o transporte após o primeiro bloco do arquivo e confere o hash após a retomada. Também envia duas páginas de uma digitalização antes do PDF e verifica os três arquivos gravados pelo Mac. O teste de loopback cobre certificado incorreto, confirmação, reconexão e revogação. Câmera, serviços do Google Play, permissões de notificações, Wi-Fi entre aparelhos reais e comportamento em diferentes fabricantes precisam de validação em hardware antes da publicação.

## Documentação

- [Arquitetura e fases](docs/ARQUITETURA.md)
- [Protocolo Nexus v1](docs/PROTOCOLO.md)
- [Sistema de design](docs/DESIGN.md)
- [Permissões e distribuição](docs/PERMISSOES-E-DISTRIBUICAO.md)
