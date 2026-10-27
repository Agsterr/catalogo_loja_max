# Planos e cobrança

O **app do cliente é grátis**. A plataforma cobra de quem usa para ganhar dinheiro: a loja e o entregador. A plataforma **não
passa dinheiro de pedido**: o cliente paga os produtos à loja e o frete ao entregador.

| Quem | O que paga | Padrão | Onde mudar |
|---|---|---|---|
| Loja | Mensalidade, com **30 dias de teste grátis** e **5 dias de tolerância** depois de vencer | R$ 49,90/mês | `BILLING_STORE_MONTHLY`, `BILLING_STORE_TRIAL_DAYS`, `BILLING_STORE_GRACE_DAYS` |
| Entregador | **5 entregas grátis por aparelho e CPF**, depois mensalidade | R$ 24,99/mês | `BILLING_COURIER_MONTHLY`, `BILLING_FREE_DELIVERIES` |
| Cliente | nada | grátis | — |

## Como funciona (loja)
- Loja nova ganha o teste grátis; as que já existiam ganham 30 dias a partir da atualização.
- Falta 7, 3 e 1 dia, no dia e depois de vencer o dono recebe aviso (sino + push) e um banner no app.
- Vencida: tem a tolerância, ainda aparece. Passou: a loja **some** da busca e da vitrine (404 para os clientes). A equipe
  continua entrando para pagar; pedidos e produtos ficam guardados. Pagou: volta na hora.
- Pagamento: Pix para a chave da plataforma (`BILLING_PIX_KEY`) com um código de referência; o admin confirma no app do lojista
  (Lojas → ícone de mensalidades). Cada pagamento libera 30 dias (a partir do vencimento se ainda não venceu; de hoje se já
  venceu). O admin também dá dias de cortesia. Um provedor de Pix automático entra atrás de `PaymentProvider`.

## Sugestão de preço (a ajustar com o mercado)
- **R$ 49,90/mês, plano único**, sem comissão e sem limite de pedidos/produtos. O diferencial contra marketplaces (que cobram
  12–27% por venda) é o preço fixo previsível; contra criadores de loja virtual (R$ 30–100/mês) é o app próprio com
  push, alerta de pedido e entrega por entregador já incluídos.
- Teste de 30 dias dá tempo de a loja cadastrar produtos e fazer as primeiras vendas antes de pagar.
- Depois de ter dados reais: planos por tamanho (ex.: Básico até 50 produtos R$ 29,90; Completo R$ 59,90 com entregador e
  relatórios) e desconto no pagamento trimestral/anual (2 meses grátis no anual). Não precisa mudar o código do app: o valor
  vem do servidor.
