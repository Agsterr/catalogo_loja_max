# Loja Max — vendas de roupas, calçados e bijuterias

Loja virtual com **API Spring** e **app Flutter**, no mesmo padrão do [Gerenciamento Max](https://github.com/Agsterr/Gerenciamento_Max):
mesmos avisos (sino + push do Firebase com fila, novas tentativas e confirmação), fotos no **Cloudflare R2**
e as mesmas regras de segurança (JWT, bloqueio que vale na hora, limite de tentativas).

| | |
|---|---|
| **API** (`backend/`) | Java 21 · Spring Boot 3.5 · Spring Security (JWT HS256) · JPA/Hibernate · Flyway · PostgreSQL |
| **App** (`mobile/`) | Flutter · um app só: vitrine para clientes e gestão para a equipe (abre conforme quem entra) |

## Funcionalidades

**Cliente (app)**
- Vitrine por departamento (**Roupas, Calçados, Bijuterias**), categorias, busca, ordenação e filtro de promoções — dá para olhar sem conta.
- Produto com fotos, preço "de/por", **tamanho/cor com estoque próprio** ("Só restam 2!") e **"Avise-me quando chegar"** para o que esgotou.
- Carrinho guardado no celular; pedido com **retirada na loja** ou **entrega** (taxa e frete grátis a partir de X), pagamento Pix/cartão/dinheiro na entrega.
- Acompanhamento do pedido com linha do tempo; cancelar enquanto a loja não separou.
- Avisos: pedido recebido/confirmado/pronto/saiu para entrega/entregue/cancelado, pagamento confirmado, produto que voltou e promoções.
- Conta: dados, trocar senha, "sair de todos os aparelhos", desligar avisos de promoção e **excluir conta** (exigência das lojas / LGPD).

**Loja (mesmo app, login da equipe)**
- Pedidos em aberto/por status, busca por código ou cliente, avançar status, marcar pago, WhatsApp do cliente.
- Produtos com tamanhos/cores, **fotos pela câmera/galeria** (comprimidas e gravadas no R2), entrada/contagem/perda de estoque com histórico.
- Promoções por período (% na loja toda, departamento, categoria ou produto) com **push para os clientes quando começa**.
- Dono: resumo de vendas (faturamento, recebido, ticket médio, mais vendidos, estoque baixo), equipe, dados da loja, bloqueio de clientes.

## Eventos e avisos (igual ao Gerenciamento Max)

Os serviços publicam eventos da loja (`event/StoreEvents`); um ouvinte na **mesma transação** grava o aviso do sino e
coloca o push na fila (`push_outbox`). O worker entrega pelo Firebase (FCM HTTP v1), tenta de novo com espera
crescente (1 min, 5 min, 30 min, 2 h) e o app confirma o recebimento (`/api/push/ack`). Sem Firebase, o app confere o
sino em segundo plano (15 min) e mostra notificação local. Detalhes em [docs/PUSH.md](docs/PUSH.md).

| Evento | Quem recebe |
|---|---|
| Pedido novo | equipe (e "pedido recebido" para o cliente) |
| Cliente cancelou | equipe |
| Tamanho/cor no estoque mínimo ou esgotado | equipe |
| Pedido confirmado / pronto / saiu / entregue / cancelado pela loja | cliente |
| Pagamento confirmado | cliente |
| Tamanho esgotado voltou ao estoque | clientes que pediram "avise-me" |
| Promoção começou | todos os celulares que aceitam promoções (com ou sem login) |

## Rodando

```bash
# banco + API (cria o dono com STORE_OWNER_EMAIL/STORE_OWNER_PASSWORD)
docker compose up --build            # API em http://localhost:8080

# ou local: PostgreSQL com banco/usuário/senha loja/loja
cd backend && mvn spring-boot:run

# app (emulador Android: 10.0.2.2 = localhost da sua máquina)
cd mobile && flutter pub get && flutter run --dart-define=API_URL=http://10.0.2.2:8080
```

### Testes
```bash
createdb -O loja loja_test
cd backend && mvn test           # TEST_DB_URL, DB_USER e DB_PASSWORD são configuráveis
cd mobile && flutter analyze && flutter test
```

## Arquitetura

```
backend/src/main/java/com/max/loja
├── shared/        erros (ProblemDetail), paginação, limite de tentativas, relógio da loja
├── security/      JWT, filtro de status da conta (bloqueio / token revogado), regras de acesso
├── auth/          cadastro, login com trava, recuperar senha por código, equipe, exclusão de conta
├── catalog/       departamentos, categorias, produtos, tamanhos/cores, estoque
├── media/         fotos: compressão (ImageIO) + Cloudflare R2 (assinatura S3 V4) ou disco
├── promotion/     promoções e preço final (PricingService)
├── order/         pedidos, itens, linha do tempo
├── event/         eventos da loja
├── notification/  sino + ouvinte dos eventos + "avise-me"
├── push/          dispositivos, fila de push, worker e envio pelo FCM
├── store/         dados da loja (retirada, entrega, frete)
└── report/        resumo de vendas
```

### Principais endpoints
| Método | Rota | Quem |
|---|---|---|
| POST | `/api/auth/register` · `/login` · `/forgot-password` · `/reset-password` | público |
| GET | `/api/public/store` · `/categories` · `/products?department=&categoryId=&q=&onSale=&sort=&page=` · `/products/{id}` · `/promotions` | público |
| POST | `/api/public/push/register` (celular sem login: só promoções) · `/api/push/ack` | público |
| GET · PUT · POST | `/api/me` · `/api/me/token` · `/password` · `/logout-all` · `/delete` · `/push-token[/remove]` · `/push-preferences` · `/watches/{productId}` | logado |
| GET · POST | `/api/notifications` · `/read` · `/{id}/read` | logado |
| POST · GET | `/api/orders` · `/api/orders/{id}` · `/{id}/cancel` | cliente |
| GET · POST · PUT · DELETE | `/api/store/products[/{id}]` · `/products/{id}/photos` · `/photos/{id}` · `/variants/{id}/stock` · `/stock/low` · `/categories` | equipe |
| GET · POST | `/api/store/orders?status=&open=&q=` · `/{id}/status` · `/{id}/paid` · `/api/store/customers` | equipe |
| GET · POST · PUT · DELETE | `/api/store/promotions` · `/api/store/reports/summary` · `/api/store/users` · `PUT /api/store/settings` · bloquear cliente | dono |

## Segurança
Resumo em [docs/SEGURANCA.md](docs/SEGURANCA.md): senha forte com BCrypt, JWT com emissor e versão (troca de senha,
bloqueio e "sair de todos" derrubam tokens já emitidos), trava de login por e-mail, limite por IP, preço e estoque
sempre calculados no servidor, cliente só vê os próprios pedidos, fotos conferidas pelo conteúdo e recomprimidas
(sem EXIF/GPS), erros sem detalhes internos, headers de segurança e segredos só em variáveis de ambiente.

## Variáveis de ambiente (API)
Veja [.env.example](.env.example). As principais: `DB_URL`/`DB_USER`/`DB_PASSWORD`, `JWT_SECRET` (≥ 32 caracteres),
`STORE_OWNER_EMAIL`/`STORE_OWNER_PASSWORD`, `APP_PUBLIC_URL`, `CORS_ORIGINS`, `R2_*` ([docs/FOTOS_R2.md](docs/FOTOS_R2.md)),
`FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` ([docs/PUSH.md](docs/PUSH.md)), `RESEND_API_KEY`/`MAIL_FROM`, `APP_TIMEZONE`.
