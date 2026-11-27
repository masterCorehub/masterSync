# Onboarding de primeira instalação (Mac) — design e plano

**Escopo (decidido com o usuário):** só o app do Mac. Conteúdo: boas-vindas e o que o app faz; parear o celular (QR); controle por Wi‑Fi (ADB e scrcpy); escolher recursos.

## Abordagem
Reaproveitar o guia de conexão que já existe (QR, autorização, instalação de ADB/scrcpy, depuração sem fio, testes de controle e áudio) e envolvê-lo num fluxo de 3 passos, em vez de reescrever. Alternativas descartadas: janela separada (duplica o estado de pareamento) e reescrever o guia (risco sem ganho).

## Fluxo
1. **Boas-vindas** — o que o app faz (6 recursos) e como a conexão é local.
2. **Conectar** — o guia atual: rede local → QR → autorizar → ferramentas (adb/scrcpy) → depuração sem fio → testes. Ao concluir ou tocar em "Agora não", segue para o passo 3.
3. **Recursos** — interruptores dos recursos do Mac (notificações, códigos 2FA, fotos, arquivos, área de transferência) e botão "Começar a usar".

Cada passo tem "Pular" (e o passo 2 já tem "Agora não"). Indicador "n de 3".

## Quando aparece
- Automático uma vez (`seen-connection-guide`), se não há rede ativada nem celular pareado (regra atual, agora `OnboardingFlow.shouldAutoShow`).
- Pode ser reaberto em Configurações → "Rever introdução".
- "Conectar Android" e "Configurar controle e áudio por Wi‑Fi" continuam abrindo direto o passo 2 (sem boas-vindas).

## Lógica pura (testada)
`OnboardingStep` (welcome, connect, features): `next`, `previous`, `position` ("1 de 3"), `isLast`. `OnboardingFlow.shouldAutoShow(seen:networkConsent:hasPeers:)`.

## Fora do escopo
Onboarding no Android; permissões do sistema do Mac além da Central de Notificações (já existe o botão em Notificações).

## Tarefas
1. RED: `OnboardingFlowTests` (passos, posição, regra de exibição, render das telas em claro/escuro). 
2. GREEN: `OnboardingFlow.swift` (lógica + `OnboardingWelcomeStep`, `OnboardingFeaturesStep`, `OnboardingHeader`).
3. Integrar no `Dashboard` (sheet por passo, finalizar → recursos, Configurações → Rever introdução).
4. Suíte completa, commit local (sem zip/push).
