# O ADB pelo Wi-Fi acompanha o celular entre redes

Data: 2026-11-26 · Status: aprovado no chat (pedido: "se eu troco de rede tenho que conectar o cabo de novo")

## Problema

O Mac guarda o endereço do ADB do celular (`IP:porta`). Ao trocar de rede (trabalho → casa), o celular ganha outro IP, mas o Mac continua tentando o antigo:

- se a sincronização já estava ativa, o laço de reconexão repete o endereço velho para sempre, mostrando só "Reconectando…";
- se o app abre na rede nova, a sincronização falha e tenta o mesmo endereço velho a cada 15 s;
- em nenhum dos casos o app pede ou descobre o IP novo.

O celular, porém, continua em contato com o Mac pelo MasterSync na rede nova, e o ADB dele (modo `tcpip`) segue escutando na mesma porta.

## Design

1. **O Mac aprende o IP de cada celular pela conexão do MasterSync.** O `LocalServer` guarda o endereço IPv4 de origem da conexão de cada celular e o apaga quando ele desconecta. Endereços IPv6 são ignorados, e um IPv4 embutido em IPv6 (`::ffff:a.b.c.d`) vira IPv4.
2. **A sincronização usa o endereço atualizado.** A cada tentativa, o laço pede ao modelo o IP atual do celular e tenta o IP novo com a **porta já guardada**. Se não responder, a tentativa seguinte volta ao endereço guardado (as duas se alternam), porque o IP do MasterSync nem sempre é onde o ADB responde (VPN, NAT). Loopback, link-local e `0.0.0.0` nunca são alvo. Quando a conexão funciona, o endereço é salvo, como já acontece hoje.
3. **A sincronização não desiste de um celular conhecido.** Se o aparelho já foi verificado antes (tem `deviceID`), o laço continua tentando e informa o motivo, em vez de terminar ou ficar mudo. Primeiro uso, sem `deviceID`, continua falhando com erro, como hoje.
4. **Reparo pelo cabo, sozinho, uma vez.** Depois de 2 falhas de **conexão** seguidas, se o celular com o mesmo `deviceID` estiver no USB **e** o celular estiver conectado ao Mac pelo MasterSync nesta rede, o Mac executa `adb -s <serial> tcpip <porta>` (a guardada, ou 5555) e tenta de novo. Isso acontece **uma vez por cabo e por endereço**: reiniciar o ADB derruba tudo o que usa o cabo, então ele não se repete.
   Só falhas de conexão contam. Erros depois de conectado (por exemplo o Android não permitir a leitura da área de transferência) mantêm a própria mensagem.
5. **Mensagens claras na seção de sincronização:**
   - 1ª falha: "Procurando o celular nesta rede…";
   - a partir da 2ª, sem cabo: "Não achei o ADB do celular nesta rede. Conecte o cabo uma vez: o Mac reativa sozinho.";
   - a partir da 2ª, com cabo e o celular nesta rede: "Reativando o ADB do celular pelo cabo…";
   - com cabo, mas já reparado: "O celular está no cabo, mas não respondeu pelo Wi-Fi. Confira se o celular e o Mac estão na mesma rede.";
   - com cabo, mas o celular fora desta rede: "Abra o MasterSync no celular, conectado à mesma rede do Mac.".

## Não objetivos

- Descobrir a porta do Depuração sem fio (aleatória) por mDNS.
- Mudar o pareamento nem o guia "Configurar Wi-Fi".
- Reiniciar o celular: depois disso o ADB pelo Wi-Fi some, e o reparo pelo cabo do item 4 o religa.

## Antiobjetivos

- Conectar a um aparelho diferente que ficou com o IP antigo: o `deviceID` continua sendo conferido.
- O laço martelar a rede: uma tentativa a cada 3 s, como hoje.
- Perder a pausa do usuário: "Parar" continua cancelando o laço.
