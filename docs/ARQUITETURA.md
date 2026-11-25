# Arquitetura

## Aplicativos e serviços

- `macOS/Sources/NexusCore` contém as mensagens, o enquadramento binário, a identidade TLS, a sessão e o servidor Bonjour. `NexusMasterSync` contém a interface SwiftUI, o Keychain e as integrações com o macOS.
- `android/app/src/main/java/com/nexus/mastersync` contém o app Kotlin. `protocol` concentra as mensagens, TLS e descoberta NSD. `security` protege as credenciais via Android Keystore. `services` conecta o transporte às APIs do Android. `ui` contém o tema e as telas Compose.
- `macOS/Tests` e `android/app/src/test` validam as regras locais. As instruções em `README.md` descrevem o teste entre dispositivos e as condições de compilação.

O Mac anuncia um serviço em `_nexus-sync._tcp` com um UUID como nome da instância. O Android inicia a conexão e repete a descoberta após falhas. O endereço alternativo do QR cobre redes que filtram multicast. O endereço IP e o nome Bonjour são pistas de roteamento. A impressão digital do certificado obtida no QR estabelece a identidade.

## Fases

1. Janela e menu nativos, QR, consentimento, Bonjour, TLS, persistência de confiança, reconexão, revogação e status dos celulares.
2. Área de transferência, arquivos e notificações com os controles individuais de cada recurso.
3. Captura, OCR, exportação e galeria remota.
4. Espelhamento, entrada remota e transporte USB.
5. Integrações adicionais, validação em hardware, segurança e distribuição.

As telas informam o estado dos recursos que ainda aguardam implementação. O estado de uma conexão vem da sessão autenticada e o estado de uma transferência vem dos bytes confirmados pelo destinatário.
