# Segurança

## Contas e sessão
- Senhas com **BCrypt (custo 12)**; regra mínima: 8+ caracteres com letras e números (API e app).
- **JWT HS256** com emissor (`loja-max`), validade de 24 h (o app renova ao abrir) e segredo de ≥ 32 caracteres
  (`JWT_SECRET`; a API não sobe com segredo curto).
- O token carrega a **versão** da conta: trocar a senha, redefinir pelo e-mail, "sair de todos os aparelhos" e mudança
  de papel invalidam na hora todos os tokens já emitidos (`AccountStatusFilter`, cache de 10 s).
- **Bloqueio** de cliente pelo dono vale na próxima requisição, inclusive com token já emitido e no login
  (`403` com `code: ACCOUNT_BLOCKED`; o app mostra a tela de bloqueio).
- **Trava de login**: 5 senhas erradas seguidas travam aquele e-mail por 15 min (`LOGIN_MAX_FAILURES`, `LOGIN_LOCK`).
  E-mail inexistente e senha errada respondem igual e levam o mesmo tempo (não revela quem tem conta).
- **Limite de tentativas por IP/e-mail** em cadastro, login, "esqueci a senha", código de redefinição, troca de senha,
  exclusão de conta e cadastro anônimo de celular (`429`).
- Recuperar senha: código de 8 caracteres, 1 hora, uso único, guardado só como hash; a resposta é sempre a mesma.
- O token fica no Keystore/Keychain (`flutter_secure_storage`); a senha nunca é guardada no celular.
- O dono é criado pelo servidor (`STORE_OWNER_*`); a senha dele não muda por e-mail.
- Exclusão de conta apaga nome, e-mail, telefone, endereços, avisos e celulares; os pedidos ficam anônimos.

## Acesso
- Papéis: `CUSTOMER` (só compras e dados dele), `STAFF` (pedidos, produtos, estoque, clientes) e `OWNER` (tudo,
  inclusive relatórios, promoções, equipe, dados da loja e bloqueio). Rotas não listadas são negadas (`denyAll`).
- Cliente só enxerga os próprios pedidos: pedido de outra pessoa responde 404 (não revela que existe).
- Funcionário removido perde o acesso e os avisos na hora.

## Pedidos e estoque
- **Preço, desconto, frete e estoque são calculados no servidor**; o app só manda tamanho/cor e quantidade.
- Linhas de estoque travadas (`SELECT … FOR UPDATE`, em ordem de id) na compra e no cancelamento: duas pessoas não
  compram a última peça e o estoque nunca fica negativo (também há `CHECK` no banco).
- Contra pedidos falsos em massa: no máximo 5 pedidos aguardando confirmação por cliente e 20 por dia; até 20 unidades
  por tamanho/cor; o dono pode bloquear a conta.

## Dados e infraestrutura
- Uploads conferidos pelo conteúdo (JPG/PNG), limite de tamanho e de megapixels, recompressão sem EXIF/GPS,
  nomes aleatórios; acesso ao R2 com token restrito ao bucket.
- Erros sempre em ProblemDetail sem stack trace/SQL; erro inesperado vira mensagem genérica (detalhe só no log).
- Headers: CSP `default-src 'none'`, `frame-ancestors 'none'`, HSTS, `nosniff`, `Referrer-Policy: no-referrer`;
  CORS só para `CORS_ORIGINS`.
- Android: release só com HTTPS (`usesCleartextTraffic=false`), sem backup automático dos dados do app.
- Container da API roda com usuário sem privilégios. Segredos só em variáveis de ambiente (`.env.example`).
