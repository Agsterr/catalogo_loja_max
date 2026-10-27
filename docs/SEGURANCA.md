# Segurança

Tudo abaixo tem teste automático (`StoreFlowIntegrationTest`, `TotpTest`), salvo onde indicado.

## Isolamento entre lojas (multi-tenant)
- Cada loja só enxerga os próprios dados: catálogo, estoque, fotos, pedidos e promoções têm `tenant_id` e o Hibernate
  aplica o filtro em toda consulta (`@TenantId`). A loja vem do JWT da equipe (não do que o app manda) ou, para o
  cliente, do endereço na URL.
- SQL puro (relatório, clientes, auditoria, celulares) filtra `tenant_id` explicitamente.
- A equipe da loja B recebe 404 ao tentar ler ou alterar produto, pedido ou estoque da loja A; o cliente não compra a
  peça de uma loja pelo endereço de outra; avisos e clientes de uma loja não aparecem para outra (teste dedicado).
- A loja vê só os clientes que compraram nela; o bloqueio que ela faz vale só nela.

## Contas e sessão
- Senhas com **BCrypt (custo 12)**; regra mínima: 8+ caracteres com letras e números (API e app). Admin da plataforma: 12+.
- **JWT HS256** com emissor (`loja-max`), 24 h (o app renova ao abrir), segredo ≥ 32 caracteres (a API não sobe com
  segredo curto). O token carrega a **versão** da conta: trocar/redefinir a senha, "sair de todos os aparelhos" e mudança
  de papel invalidam na hora todos os tokens já emitidos.
- **Verificação em duas etapas** (TOTP, compatível com Google Authenticator/Authy): opcional para todos, recomendada à
  equipe. O segredo fica **cifrado com AES-256-GCM** no banco (`APP_ENCRYPTION_KEY`); o admin da plataforma pode desligar
  para quem perdeu o celular.
- **Bloqueio** (conta, pelo admin da plataforma; loja inteira, idem) vale na próxima requisição, inclusive com token já
  emitido e no login (`403` `ACCOUNT_BLOCKED`; o app mostra a tela de bloqueio).
- **Trava de login**: 5 senhas (ou códigos) errados seguidos travam aquele e-mail por 15 min. E-mail inexistente e senha
  errada respondem igual e levam o mesmo tempo.
- **Limite de tentativas no banco** (vale com várias instâncias da API; chaves guardadas como hash): login por IP e por
  e-mail, cadastro, abrir loja, "esqueci a senha", código de redefinição, 2 etapas, troca de senha, exclusão, celular anônimo.
- Recuperar senha: código de 8 caracteres, 1 hora, uso único, guardado só como hash.
- Token no Keystore/Keychain (`flutter_secure_storage`); a senha nunca é guardada no celular.

## Auditoria
- Ficam registrados (com IP): entradas, tentativas erradas, travas, trocas e redefinições de senha, 2 etapas ligada/
  desligada, "sair de todos", exclusão de conta, funcionário criado/removido, cliente bloqueado/desbloqueado, dados da
  loja alterados, produto excluído, promoção salva, loja/conta bloqueada pela plataforma.
- Cada pessoa vê os **acessos da própria conta**; o dono vê a **auditoria da loja**. Mudanças de pedido e estoque têm
  ainda a linha do tempo do pedido e o histórico do estoque (com quem fez).

## Acesso
- Papéis: `CUSTOMER`, `STAFF` (pedidos, produtos, estoque, clientes), `OWNER` (tudo da loja, inclusive relatórios,
  promoções, equipe, dados, auditoria e bloqueio) e `PLATFORM_ADMIN` (lojas e contas). Rotas não listadas: `denyAll`.
- Cliente só enxerga os próprios pedidos (o de outra pessoa responde 404).

## Pedidos e estoque
- **Preço, desconto, frete e estoque são calculados no servidor**; o app só manda tamanho/cor e quantidade.
- Linhas de estoque travadas (`SELECT … FOR UPDATE`, em ordem de id): a última peça não é vendida duas vezes e o estoque
  nunca fica negativo (`CHECK` no banco).
- Contra pedidos falsos em massa: até 5 aguardando confirmação por cliente em cada loja, 20 por dia, 20 unidades por
  tamanho/cor; a loja pode bloquear o cliente.

## Dados, código e infraestrutura
- Uploads conferidos pelo conteúdo (JPG/PNG), limite de tamanho e de megapixels, recompressão sem EXIF/GPS, nomes
  aleatórios; token do R2 restrito ao bucket.
- Erros em ProblemDetail sem stack trace/SQL; erro inesperado vira mensagem genérica.
- Headers: CSP `default-src 'none'`, `frame-ancestors 'none'`, HSTS, `nosniff`, `Referrer-Policy: no-referrer`; CORS só
  para `CORS_ORIGINS`.
- Android: release só HTTPS, sem backup automático dos dados do app.
- Container da API sem root; segredos só em variáveis de ambiente.
- GitHub: **CodeQL** (análise de segurança do código a cada PR e semanal) e **Dependabot** (dependências com falha
  conhecida viram PR). *Não testado aqui: rodam no GitHub.*

## Ainda não coberto
- Teste de invasão por terceiros.
- Push no iPhone (falta a chave APNs da Apple).
