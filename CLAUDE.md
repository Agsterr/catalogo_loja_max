# Loja Max — instruções para agentes

## Projeto
- `backend/` Spring Boot (Java 21, PostgreSQL, Flyway) e `mobile/` app Flutter único (cliente + gestão da loja).
- Plataforma multi-loja: entidade da loja estende `TenantEntity` (`@TenantId`); SQL puro filtra `tenant_id` sempre.
  Rotas do cliente levam a loja na URL (`/api/public/stores/{slug}`, `/api/stores/{slug}`); a equipe usa o claim do JWT.
- Mesmo padrão do Gerenciamento Max: eventos da loja → sino + fila de push (FCM), fotos no Cloudflare R2, JWT com revogação.
- Mudou uma tela? Regere as imagens: `cd mobile && flutter test screenshots/telas_test.dart`.
- Textos, commits e PRs em português.

## Antes de enviar
- `cd backend && mvn test` (precisa de PostgreSQL com o banco `loja_test`, usuário/senha `loja`).
- `cd mobile && flutter analyze && flutter test`.
- Mudança no banco = nova migração em `backend/src/main/resources/db/migration` (nunca editar uma já publicada).
- Nunca grave senhas, tokens ou chaves no repositório: ficam no `.env` do servidor / *secrets* do GitHub (veja `.env.example`).
