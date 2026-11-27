# Botões rápidos do celular na Visão geral — plano

**Pedido (design novo):** no cartão do aparelho da Visão geral, no lugar das linhas de informação, seis botões funcionais:
Não perturbe · Silencioso · Tocar celular · Hotspot · Lanterna · Bloquear.

## O que cada botão faz de verdade

| Botão | Como | Estado mostrado |
|---|---|---|
| Não perturbe | já existe (`dndSet`/`dndState`, precisa da permissão de Não Perturbe do MasterSync) | Ativado/Desativado |
| Tocar celular | já existe (`ringPhone`, precisa de "Localizar celular" ligado no Android) | "Encontrar" |
| Silencioso | **novo**: `deviceControl` ringer → o app Android muda o modo de toque (silencioso ↔ normal). Silencioso exige a mesma permissão de Não Perturbe | Som normal / Silencioso / Vibrar |
| Lanterna | **novo**: `deviceControl` torch → `CameraManager.setTorchMode` (não precisa de permissão) | Acesa / Apagada |
| Bloquear | **ADB sem fio** (o Mac já usa): `input keyevent 223` (apaga a tela e bloqueia) | "Tela do <celular>" |
| Hotspot | **ADB sem fio**: o Android 17 não deixa nenhum app nem o ADB ligar o hotspot, e nenhuma linha do `dumpsys` diz com segurança se ele está ligado; então o botão **abre a tela de Hotspot do celular** (`android.settings.TETHER_SETTINGS` → `SecTetherSettingsActivity`, conferida no aparelho) | "Abrir ajustes" (sem Ligado/Desligado) |

Descobertas no celular real (SM-S916B, Android 17): `cmd audio` não tem modo de toque, não há `cmd torch`, nem `start-softap`/tethering pelo shell. Por isso Silencioso e Lanterna passam pelo app, e o Hotspot só abre os ajustes.

## Tarefas
1. **Android:** `DeviceControls` (lanterna, modo de toque) + mensagens `deviceControlsRequest`/`deviceControl` → `deviceControlsState`; capacidade `deviceControls`. Teste unitário da lógica pura do modo de toque.
2. **Mac, protocolo e regras puras:** campos novos em `Message`; `QuickControls` (lista dos 6 botões, estado, habilitação); testes.
3. **Mac, ADB:** `lockScreen`, `openHotspotSettings` em `ADBClipboardSession`; modelo com estado e ações (`NexusModel`).
4. **Mac, UI:** cartão do aparelho da Visão geral com a grade de 6 botões; atualização periódica do estado.
5. Suíte inteira, build Android (compilar e testar), revisão.

Sem gerar ZIP nem APK (só quando o usuário pedir).
