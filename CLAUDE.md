# Loja Max — instruções para agentes

## Projeto
- `backend/` Spring Boot (Java 21, PostgreSQL, Flyway) e `mobile/` app Flutter único (cliente + gestão da loja).
- Mesmo padrão do Gerenciamento Max: eventos da loja → sino + fila de push (FCM), fotos no Cloudflare R2, JWT com revogação.
- Textos, commits e PRs em português.

## Antes de enviar
- `cd backend && mvn test` (precisa de PostgreSQL com o banco `loja_test`, usuário/senha `loja`).
- `cd mobile && flutter analyze && flutter test`.
- Mudança no banco = nova migração em `backend/src/main/resources/db/migration` (nunca editar uma já publicada).
- Nunca grave senhas, tokens ou chaves no repositório: ficam no `.env` do servidor / *secrets* do GitHub (veja `.env.example`).
