# Entregadores — desenho e etapas

Entregadores se cadastram num app próprio, a plataforma aprova, e as entregas das lojas que usam "entregador da
plataforma" aparecem num mural por região; o primeiro que aceitar leva.

## Fluxo
1. Entregador se cadastra (cidade, veículo, raio de atuação) → `PENDING` → admin da plataforma aprova.
2. Loja liga **"Entrega por entregador da plataforma"** (precisa ter a localização marcada).
3. Cliente pede com entrega: informa a localização, o servidor calcula os km e a taxa (`base + km × valor`, mínimo, máximo de km).
4. Pedido fica **pendente** (loja e cliente avisados). O cliente paga (etapa 1: a loja marca "pago"; etapa 2: Pix online).
5. Loja **confirma** → com o pagamento feito, a corrida abre (`OPEN`) e os entregadores online da região recebem push.
6. Um entregador aceita (atômico: só um consegue) → loja e cliente avisados. O endereço completo só aparece depois do aceite.
7. **Coleta**: o entregador informa o código de 4 dígitos que a loja vê no pedido → pedido vira "saiu para entrega".
8. **Entrega**: o entregador informa o código que o cliente vê no pedido → pedido "entregue".
9. Ninguém aceitou em 30 min → `EXPIRED`, a loja é avisada e pode chamar de novo ou entregar por conta própria.

## Etapas
- **Etapa 1 (esta)**: cadastro/aprovação, mural por região, aceitar/coletar/entregar com códigos, ganhos, app do entregador,
  painel nos apps da loja e do admin. Pagamento ainda confirmado pela loja.
- **Etapa 2**: Pix online (provedor atrás da interface `PaymentProvider`, webhook confirma o pagamento sozinho), estorno.
- **Etapa 3**: rastreio ao vivo, avaliações, bônus quando ninguém aceita, repasse/saque dos ganhos, comissão.

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
- Localização do cliente: guardada no pedido só para entrega por entregador (necessária para despachar).
