# Loja Max — instruções para agentes

## Projeto
- `backend/` Spring Boot (Java 21, PostgreSQL, Flyway) e `mobile/`: apps Flutter `cliente` (Loja Max) e `lojista`
  (Loja Max Lojista, também do admin da plataforma), pacote comum `core` e gerador de imagens `telas`.
- Plataforma multi-loja: entidade da loja estende `TenantEntity` (`@TenantId`); SQL puro filtra `tenant_id` sempre.
  Rotas do cliente levam a loja na URL (`/api/public/stores/{slug}`, `/api/stores/{slug}`); a equipe usa o claim do JWT.
- Mesmo padrão do Gerenciamento Max: eventos da loja → sino + fila de push (FCM), fotos no Cloudflare R2, JWT com revogação.
- Mudou uma tela? Regere as imagens: `cd mobile/telas && flutter test telas_test.dart`.
- Textos, commits e PRs em português.

## Publicar (deploy)
- Sessão na nuvem que só consegue enviar para o próprio branch (`ccr-*`): basta dar push nele.
  `.github/workflows/cloud-to-main.yml` mescla na `main` (cria se não existir) e dispara o deploy (`backend/`, `deploy/`).
  Antes, rode `git pull origin main` (quando existir) para evitar conflito; com conflito o workflow falha e nada é publicado.

## Antes de enviar
- `cd backend && mvn test` (precisa de PostgreSQL com o banco `loja_test`, usuário/senha `loja`).
- `cd mobile/<core|cliente|lojista|telas> && flutter analyze` e `flutter test` em `cliente` e `lojista`.
- Mudança no banco = nova migração em `backend/src/main/resources/db/migration` (nunca editar uma já publicada).
- Nunca grave senhas, tokens ou chaves no repositório: ficam no `.env` do servidor / *secrets* do GitHub (veja `.env.example`).
