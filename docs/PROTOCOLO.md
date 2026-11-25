# Protocolo Nexus v1

## Transporte e confiança

O servidor macOS publica `_nexus-sync._tcp` no domínio local. O transporte é TCP persistente com TLS 1.3. O Mac gera uma identidade ECDSA P-256 e conserva a chave privada no Keychain. O Android valida a data e o SHA-256 do certificado DER com o valor recebido no QR. A comparação é feita dentro da validação TLS, antes de qualquer credencial ser enviada. O protocolo não usa uma autoridade certificadora externa.

O QR contém JSON com `version`, `serverId` (UUID minúsculo), `host` (IPv4 alternativo), `port`, `pin` (SHA-256 em Base64 padrão), `token` (32 bytes aleatórios em Base64) e `expiresAt` (Unix em segundos). A validade é de três minutos. Só um pedido pode reservar o token e a tela do Mac exibe o nome e o modelo declarados pelo Android antes da decisão. A reserva expira junto com o QR.

Após autenticar o servidor, o cliente envia `pair` com o token ou `resume` com uma credencial previamente aprovada. No pareamento, o cliente já envia uma credencial aleatória de 32 bytes, guardada localmente como pendente antes do envio. O Mac grava a autorização antes de responder. Isso permite recuperar uma confirmação perdida durante uma falha da rede. A confirmação é `accepted`, incluindo o identificador e o nome do Mac. Um `reject` com `message` encerra a sessão. Ao revogar o dispositivo, o Mac exclui a credencial persistente antes de fechar a sessão. O Android pode esquecer o registro e o seu material de autenticação no próprio aparelho.

## Enquadramento

Cada mensagem tem um comprimento de 4 bytes sem sinal, inteiro big-endian, seguido por 1 a 262.144 bytes UTF-8 de JSON, sempre dentro do TLS. O primeiro campo lógico é `type`. `version: 1` acompanha a autenticação. O servidor aceita somente uma sessão ativa por dispositivo e até 16 conexões pendentes ou ativas. Cada lado fecha o socket após um erro de enquadramento. O Android envia `ping` periodicamente e recebe `pong` para detectar conexões interrompidas.

Campos de autenticação:

| Tipo | Campos |
| --- | --- |
| `pair` | `version`, `serverId`, `id`, `name`, `model`, `token`, `credential` |
| `resume` | `version`, `serverId`, `id`, `credential` |
| `accepted` | `version`, `serverId`, `name` |
| `reject` | `message` |
| `status` | `battery` (0–100 ou ausente), `charging` |
| `ping`, `pong` | nenhum |

As credenciais nunca aparecem no anúncio Bonjour, nos logs ou nos eventos da interface. Os nomes declarados por um par ainda pendente servem à confirmação visual. Uma revisão de segurança externa e a validação em redes reais integram a fase de distribuição.

## Mensagens após autenticação

- `capabilities` mapeia recursos habilitados nos dois aplicativos. As opções são independentes e começam desativadas. Os campos incluem `clipboard`, `files`, `notifications`, `gallery`, `scanner`, `mirror`, `findPhone` e `mediaControl`.
- `clipboard` carrega `text` UTF-8 de até 32 KiB e aceita a marca `sensitive`. A escrita recebida atualiza o marcador local para suprimir o eco.
- Quando ambos anunciam `clipboardImages`, `clipboardImageOffer` anuncia MIME, UUID, tamanho até 8 MiB e SHA-256. `clipboardImagePart` envia até 128 KiB por bloco. `clipboardImageAck` confirma o próximo byte, e `clipboardImageDone` libera a imagem para colar após validação do tamanho e digest. A imagem usa a autorização da área de transferência.
- Arquivos começam em `fileOffer` com UUID, nome, MIME, tamanho até 4 GiB e SHA-256 em Base64. O destinatário devolve `fileOffset` com o tamanho do fragmento presente no disco. Cada `fileData` traz UUID, deslocamento e até 64 KiB em Base64. `fileAck` confirma o byte seguinte. Após `fileDone`, o destinatário valida o SHA-256 e move o conteúdo para o nome final antes de confirmar com `fileComplete`. `fileError` encerra o item. Uma sessão recuperada reenvia a oferta com o mesmo UUID.
- `notice` leva identificador opaco, nome e ícone do aplicativo, agrupamento, horário, conteúdo filtrado e disponibilidade de resposta. `noticeRemoved`, `noticeDismiss` e `noticeReply` são limitados a notificações identificadas e ainda presentes no Android.
- `scanRequest` abre um pedido de autorização no Android. A operação responde por `scanStatus` e usa o protocolo de arquivos. As páginas JPEG chegam antes do PDF e incluem `scanPage: true` na oferta para o Mac abrir a prévia depois de salvar. Versões anteriores podem receber o JPEG ignorando o campo opcional.
- `galleryList`, `galleryAlbums`, `galleryThumb` e `galleryFetch` solicitam paginação, álbuns, miniaturas e originais a partir do MediaStore autorizado. As respostas usam `galleryPage`, `galleryAlbumList`, `galleryImage` e `galleryStatus`. Originais seguem pelo protocolo de arquivos.
- A galeria de revisão 2 aceita `query`, `addedFrom` inclusivo, `addedBefore` exclusivo e `order`. As datas usam segundos Unix e representam adição ao MediaStore. `galleryPreview` solicita uma prévia JPEG em `galleryPreviewImage` e usa um UUID de correlação separado de `mediaId`. Para abrir um original, `galleryFetch` pode fornecer `transferId`, reutilizado no protocolo de arquivos. `backgroundConnection` informa se o serviço de conexão do Android está ativo.
- `screenRequest` inclui UUID e parâmetros de qualidade. A confirmação do Android precede `screenActive` e os quadros JPEG em `screenFrame`. `screenAck` libera o próximo quadro. `screenStop` e `screenEnded` encerram a sessão de visualização.
- `ringPhone` e `mediaCommand` pedem ações locais permitidas nas configurações Android. `actionStatus` informa o resultado.
