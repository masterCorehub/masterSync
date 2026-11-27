# Tela de Arquivos nova + armazenamento interno do celular — plano

Referência: duas capturas do design (abas "Transferências" e "Arquivos do Pixel", coluna da direita com Armazenamento, Onde salvar e opções).

## Decisões
- **Armazenamento interno pelo ADB sem fio** (o Mac já tem o celular autorizado): `ls`, `df`, `find` e `adb pull`. Não muda o app Android, não pede a permissão "todos os arquivos" e não exige APK novo. Limites: precisa do controle por Wi-Fi configurado; `Android/data` fica fora (o Android bloqueia até para o shell).
- Só se lê **dentro de `/sdcard`**; todo caminho vem de lista própria e é validado (sem `..`, sem caracteres de shell) antes de chegar ao ADB.
- Baixar do celular = `adb pull` para `~/Downloads/MasterSync` (pastas viram pastas; abre no Finder).
- **Armazenamento**: livre/total reais (`df`). O design divide o uso em Fotos, Apps, WhatsApp e Sistema; só dá para somar com segurança as pastas do cartão (Fotos e vídeos = DCIM+Pictures+Movies, WhatsApp, Música, Documentos); o resto é "Outros e sistema". Sem categorias inventadas.
- **Onde salvar**: mostra as pastas reais com "Mostrar no Finder" (os recebidos ficam na pasta do app; mudar de lugar exigiria migrar arquivos, fica fora). "Alterar" do design não entra.
- **Abrir ao receber** e **Compactar pastas** são opções reais. "Confirmar no Pixel" do design não existe (o ADB não pede confirmação), fica de fora.
- Pastas arrastadas: com "Compactar pastas" ligado viram `.zip` (via `ditto`) antes do envio; desligado, a pasta é recusada com aviso.

## Tarefas
1. Regras puras + testes: `PixelPath` (validação/pai/migalhas), `PixelListing.parse` (`ls -la`), `PixelStorage.parse` (`df`) e categorias, `TransferFilter`/linhas de transferência, `FolderZip`.
2. ADB: `listDirectory`, `storage`, `countItems`, `pull` na `ADBClipboardSession` + `PixelFilesModel` (estado, erros, cache).
3. UI aba Transferências (zona de soltar com Colar/Escolher, filtros, linhas com ações, Limpar concluídas) + opções.
4. UI aba "Arquivos do Pixel" (pastas com contagem, navegação por migalhas, seleção e Baixar) + coluna Armazenamento / Onde salvar.
5. Suíte, revisão.

Sem gerar ZIP nem APK até o usuário pedir.
