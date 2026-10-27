# Entregadores — desenho e etapas

Entregadores se cadastram num app próprio, a plataforma aprova, e as entregas das lojas que usam "entregador da
plataforma" aparecem num mural por região; o primeiro que aceitar leva.

## Quem recebe o quê (a plataforma não passa dinheiro de pedido)
- **Produtos**: o cliente paga direto à loja, do jeito que a loja combinar (Pix, cartão...). A loja marca "pago".
- **Frete**: pago **direto ao entregador**. Pelo cliente (em dinheiro ou Pix, na entrega) ou, quando o pedido passa do valor de
  "frete grátis a partir de" da loja, pela loja (na coleta). O total do pedido não inclui o frete.
- **Plataforma**: o único dinheiro que passa por ela é a **assinatura do entregador** (R$ 24,99 por mês, depois de 5 entregas grátis).

## Fluxo
1. Entregador se cadastra (CPF, cidade, veículo, raio) → `PENDING` → admin da plataforma aprova.
2. Loja liga **"Entrega por entregador da plataforma"** (precisa da localização marcada) e escolhe o frete grátis a partir de X (opcional).
3. Cliente pede com entrega: informa a localização; o servidor calcula os km e o frete (`base + km × valor`, mínimo, máximo de km).
4. Pedido fica **pendente** (loja e cliente avisados). O cliente paga a loja; a loja marca "pago" e **confirma**.
5. Com o pedido pago e confirmado a corrida abre (`OPEN`) e os entregadores online da região recebem push.
6. Um entregador aceita (atômico: só um consegue; antes, confere entregas grátis/assinatura) → loja e cliente avisados.
   O endereço completo só aparece depois do aceite.
7. **Coleta**: o entregador informa o código de 4 dígitos que a loja vê no pedido → "saiu para entrega".
8. **Entrega**: o entregador informa o código que o cliente vê no pedido → "entregue" (e conta uma entrega grátis, se for o caso).
9. Ninguém aceitou em 30 min → `EXPIRED`; a loja pode chamar de novo, entregar por conta própria ou cancelar.

## Entregas grátis, assinatura e antifraude
- **5 entregas grátis por aparelho e por CPF** (vale o menor saldo). O app manda o ID do aparelho (`X-Device-Id`: ANDROID_ID /
  identifierForVendor); o servidor guarda só uma impressão digital (HMAC). Trocar e-mail ou CPF no mesmo aparelho **não renova**.
- **CPF único**: validado (dígitos verificadores), guardado cifrado (AES-GCM) + impressão digital para impedir segundo cadastro.
  Excluir a conta apaga o CPF e os dados pessoais, mas mantém a impressão digital e o saldo (não dá para renovar excluindo).
- Acabaram as grátis → o aceite responde **402** (`SUBSCRIPTION_REQUIRED`) e o app oferece a **assinatura**: `POST
  /api/courier/subscription/checkout` gera a cobrança (R$ 24,99, 30 dias), mostra a chave Pix da plataforma e um código de
  referência; o admin confirma o recebimento (`/api/platform/courier-payments/{id}/confirm`) e a assinatura é liberada.
  Um provedor de pagamento automático entra atrás de `PaymentProvider` (webhook chama `CourierBilling.confirm`).
- Limites conhecidos: o ID do aparelho muda com reset de fábrica (Android) ou ao desinstalar todos os apps do desenvolvedor (iOS);
  quem tem vários aparelhos tem 5 em cada. A impressão digital não impede um aparelho "rooteado" que falsifica o ID.

## Etapas
- **Etapa 1**: cadastro/aprovação, mural por região, aceite/coleta/entrega com códigos, ganhos, app do entregador, painel
  nos apps da loja e do admin.
- **Etapa 2 (esta)**: frete pago direto ao entregador, 5 grátis por aparelho/CPF, assinatura R$ 24,99 com confirmação do admin.
- **Etapa 3 (esta)**: rastreio ao vivo, avaliação do entregador e bônus da loja (veja abaixo).
- **Etapa 2b**: cobrança automática da assinatura (Pix com QR + webhook) — precisa de conta num provedor.
- **Depois**: cobrança automática, localização em segundo plano (serviço em primeiro plano), mapa dentro do app, bônus automático.

## Rastreio, avaliação e bônus (etapa 3)
- **Rastreio**: o app do entregador manda a posição a cada ~15 s enquanto a corrida está ativa e o app está aberto
  (`POST /api/courier/jobs/{id}/location`). Só a **última** posição é guardada (sem histórico de trajeto) e some do alcance
  quando a corrida acaba. A loja vê desde o aceite; o cliente, depois da coleta (`GET .../orders/{id}/tracking`), com distância e
  previsão por linha reta (20 km/h, fator de rua 1,3) — é uma estimativa. "Ver no mapa" abre o mapa do aparelho (sem chave de mapas).
  Limitação: sem permissão de localização em segundo plano, a posição só atualiza com o app aberto.
- **Avaliação**: o cliente dá 1 a 5 estrelas, uma vez por pedido entregue (`POST .../orders/{id}/rate-courier`). A média aparece na
  conta do entregador, no pedido (loja e cliente) e na lista do admin.
- **Bônus**: quando ninguém aceita (ou para chamar mais rápido), a loja soma de R$ 0 a R$ 50 ao frete — **dinheiro da loja**, pago
  direto ao entregador na coleta. Reabre a corrida, o push e o mural mostram o valor com bônus; numa corrida aberta só dá para
  aumentar o bônus. Os ganhos do entregador somam frete + bônus.

## Pensando em escala
- Módulo `delivery` isolado; `delivery_job` **não é por loja** (entregador vê corridas de várias lojas) e guarda um
  *snapshot* do que o entregador precisa — ele nunca lê o pedido nem os dados da loja diretamente.
- Aceite com um `UPDATE ... WHERE status = 'OPEN'` (sem lock longo, sem corrida entre entregadores); trava só por entregador
  (limite de corridas ativas).
- Mural com pré-filtro por caixa de coordenadas (índice parcial só nas corridas abertas) e distância calculada no banco.
- Push em lote pela fila existente (`push_outbox`: reenvio, confirmação, deduplicação); só os N entregadores mais próximos.
- Expiração em lote com `FOR UPDATE SKIP LOCKED`: várias instâncias da API podem rodar o agendador sem duplicar.
- Preço atrás de `DeliveryPricing` (hoje fórmula única por propriedades `app.delivery.*`; depois, tabela por cidade).
- Ações de corrida rodam numa única transação **no tenant do pedido** (`TenantRunner`), com o pedido travado primeiro
  (mesma ordem de lock em todos os caminhos, sem deadlock).
- Localização do cliente: guardada no pedido só para entrega por entregador (necessária para despachar); apagada ao excluir a conta.
- Configuração: `app.delivery.*` (preço do frete, raio máximo, expiração) e `app.billing.*` (mensalidade, entregas grátis, chave Pix).
