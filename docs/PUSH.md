# Avisos e push (Firebase)

Funciona igual ao Gerenciamento Max. Sem configurar nada, os avisos já aparecem no **sino** do app e o Android
confere o sino em segundo plano a cada ~15 min (notificação local). Com o Firebase configurado, o aviso chega **na hora**,
mesmo com o app fechado (a consulta em segundo plano passa a ser só reserva, a cada 1 h, sem repetir o aviso).

## Como funciona
1. Os serviços publicam eventos (`StoreEvents`): pedido novo, mudança de status, pago, estoque baixo/esgotado,
   tamanho que voltou e promoção que começou.
2. `StoreEventListener` (mesma transação) grava o aviso do sino (`notification`) e enfileira o push (`push_outbox`)
   para cada celular de quem deve receber. Cada aviso tem uma chave: o mesmo aviso não entra duas vezes.
3. `PushOutboxWorker` (a cada 10 s, `app.push.worker-ms`) envia pelo FCM HTTP v1. Falhou: tenta de novo em
   1 min, 5 min, 30 min e 2 h (até 5 tentativas, depois `DEAD`). Código de celular inválido apaga o aparelho.
   Parado há mais de 24 h vira `EXPIRED`; o que já terminou some depois de 30 dias.
4. O app confirma o recebimento em `POST /api/push/ack` (`SENT` → `RECEIVED`), com o código do aviso e o do celular.

Celulares: `POST /api/me/push-token` liga o celular à conta (equipe recebe os avisos da loja dela; cliente, os dos
pedidos dele em qualquer loja). Ao abrir a vitrine de uma loja, o app chama `POST /api/public/stores/{slug}/push` e o
celular passa a **seguir** aquela loja (recebe as promoções dela, com ou sem login; não mexe em celular já ligado a uma
conta). Ao sair, `POST /api/me/push-token/remove`. Promoções podem ser desligadas em *Conta*
(`PUT /api/me/push-preferences`). O aviso leva o endereço da loja (`slug`), e o app abre o pedido/produto na loja certa.

Canais do Android: `pedidos` (pedidos e estoque) e `promocoes` (promoções e "chegou!").

## Configurar uma vez
1. https://console.firebase.google.com → **Criar projeto**.
2. **Adicionar app → Android** com o pacote `io.github.agsterr.lojamax`. Do `google-services.json` copie
   (não precisa ir para o repositório):
   | Secret do GitHub / `--dart-define` | Campo |
   |---|---|
   | `FIREBASE_API_KEY` | `client[0].api_key[0].current_key` |
   | `FIREBASE_APP_ID` | `client[0].client_info.mobilesdk_app_id` |
   | `FIREBASE_SENDER_ID` | `project_info.project_number` |
   | `FIREBASE_PROJECT_ID` | `project_info.project_id` |
3. Firebase → ⚙️ *Configurações do projeto → Contas de serviço* → **Gerar nova chave privada** (JSON). No servidor,
   no `.env` (nunca no repositório): `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64=` + saída de `base64 -w0 arquivo.json`.
4. Build do app com os quatro `--dart-define=FIREBASE_*` (o CI já passa os secrets).

iPhone: exige chave APNs da Apple (conta de desenvolvedor) — ainda não configurado; no iOS ficam o sino e os avisos locais.
