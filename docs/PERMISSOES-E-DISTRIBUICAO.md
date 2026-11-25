# Permissões e distribuição

Requisitos conferidos em 24 de novembro de 2026.

| Permissão | Plataforma | Finalidade |
| --- | --- | --- |
| Rede local e Bonjour | macOS | Anunciar e aceitar conexões Nexus na mesma rede. O app pede essa autorização quando você ativa a rede local. |
| Internet e estado da rede | Android | O nome da permissão cobre sockets e descoberta, inclusive na rede local. O transporte Nexus usa somente endereços locais e loopback USB. |
| Câmera | Android | Ler o QR na tela do Mac. A digitalização abre o fluxo de câmera do ML Kit por ação local. |
| Notificações do próprio app | Ambos | Exibir alertas no Mac e indicar serviços em segundo plano e captura ativa no Android. |
| Acesso às notificações | Android | Espelhar notificações dos aplicativos permitidos, oferecer ações de resposta e consultar a sessão de mídia se você ativar esse controle. |
| Fotos e vídeos | Android | Consultar a galeria com o alcance concedido pelo usuário. Android 14 ou superior permite selecionar mídias. O seletor de arquivos Android funciona independentemente. |
| Captura de tela | Android | Cada sessão usa o consentimento de MediaProjection e um serviço em primeiro plano com ação de parada. |
| Método de entrada padrão | Android | O usuário habilita e seleciona o Teclado Nexus para sincronizar o conteúdo que copia em outros apps. O teclado digita no campo ativo, e a sincronização observa as alterações da área de transferência quando autorizada. |
| Depuração USB | Android | Usar o túnel ADB opcional ou o controle externo pelo scrcpy. O próprio Android pede autorização do computador. |

Credenciais ficam no Keychain do macOS e protegidas por uma chave do Android Keystore. O histórico de texto é opcional e armazenado na pasta privada de suporte do app no Mac. Ele pode ser apagado pela interface. O pareamento autoriza a conexão. Cada integração tem controles próprios. Cada aparelho mantém seus arquivos e digitalizações localmente.

## Google Play

A versão Android declara `targetSdk 36`, o mínimo indicado pelo Google Play para novos envios e atualizações de apps de telefone desde 31 de agosto de 2026. Uma publicação exige AAB de release assinado e preenchimento da ficha de segurança de dados, incluindo o uso das APIs do ML Kit. [Requisito de API de destino](https://support.google.com/googleplay/android-developer/answer/11926878) · [Privacidade do ML Kit](https://developers.google.com/ml-kit/terms)

A galeria remota pede permissões de mídia quando o usuário a ativa. O acesso amplo e persistente está sujeito à declaração e revisão do Google Play. Se a análise não aprovar esse escopo, uma variante para a loja pode manter a seleção explícita e envio pelo seletor do sistema. Declarações de serviço em primeiro plano devem cobrir a conexão visível e a captura iniciada pelo usuário. [Política de permissões](https://support.google.com/googleplay/android-developer/answer/16558241) · [Tipos de serviços em primeiro plano](https://developer.android.com/develop/background-work/services/fgs/service-types)

O aplicativo usa o consentimento por sessão de MediaProjection. A entrada por USB fica na ferramenta externa autorizada e a versão Android não registra um AccessibilityService. [Consentimento de captura](https://developer.android.com/media/grow/media-projection)

### Instalação direta

O Play Protect pode bloquear APKs instalados diretamente quando declaram um leitor de notificações, mesmo se o acesso depender de consentimento no app. A variante `direct` deixa o serviço e o código de leitura fora do pacote. O espelhamento de notificações e os controles de reprodução ficam na variante `full`. Os avisos que o próprio Nexus exibe durante o uso funcionam nas duas edições. [Orientações do Play Protect](https://developers.google.com/android/play-protect/warning-dev-guidance#app_blocked_to_protect_your_device)

O identificador `com.nexus.mastersync.direct` mantém a edição direta instalável ao lado da edição completa. Cada edição mantém seu próprio pareamento. O Play Console aceita o APK de depuração da edição completa no compartilhamento interno de apps e disponibiliza um link de instalação para os testadores. [Compartilhamento interno de apps da Google Play](https://support.google.com/googleplay/android-developer/answer/9844679?hl=pt-BR)

## macOS

O pacote local usa assinatura ad hoc e a distribuição com scrcpy/ADB destina-se ao canal independente. Para distribuí-lo publicamente, prepare Developer ID, Hardened Runtime, notarização e validação em um Mac limpo. Usuários instalam separadamente as ferramentas de controle USB. [Revisão e distribuição Apple](https://developer.apple.com/app-store/review/guidelines/)

Uma variante Mac App Store precisa ativar App Sandbox e entitlements de rede e arquivos adequados, além de retirar a integração que abre o executável externo do controle USB. A Apple exige uma instalação autocontida e impõe outras condições às integrações e à execução de processos. A área de transferência do macOS pode ainda pedir permissão de leitura de acordo com a versão e os ajustes do aparelho. [Requisitos específicos da Mac App Store](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility) · [Privacidade de rede local](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

A futura webcam deve ser uma extensão Core Media I/O com as capacidades System Extension e App Groups, assinatura provisionada e aprovação visível no macOS. Essa extensão também tem uma rota documentada para distribuição pela App Store. [Documentação de câmera da Apple](https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o)
