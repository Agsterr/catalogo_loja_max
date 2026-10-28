# Loja web

Cada loja tem uma vitrine na web em `https://<site>/loja/<slug>` (o mesmo `slug` do app). O lojista copia ou compartilha o
link em **Mais → Link da minha loja na web** (app Loja Max Lojista).

- Arquivos: `deploy/site/loja.html`, `loja.css`, `loja.js` (sem framework; carrega rápido no celular). O nginx responde
  `/loja/*` com `loja.html` e o JavaScript lê o endereço (`/loja/<slug>`, `/loja/<slug>/p/<id>`, `/loja/<slug>/pedido/<id>`).
- Usa a **mesma API** dos apps (`/api/public/stores/{slug}/...` e `/api/stores/{slug}/orders`), pelo mesmo domínio: sem CORS.
- Vitrine com busca, departamentos, categorias, promoções e ordenação; produto com fotos por cor, tamanho/cor com estoque,
  sacola conferida com a loja (preço e estoque de agora), cadastro/entrada (2 etapas inclusive), retirada ou entrega
  (taxa por distância com "Calcular a entrega"), pagamento combinado e acompanhamento do pedido.
- A sacola fica no navegador (`localStorage`, uma por loja); o login é a mesma conta do app.
- Segurança: tudo é montado com `textContent` (nada de `innerHTML`), imagens só `https:` ou do próprio site, CSP no nginx.
- Testar sem o servidor: `node` com um servidor estático que devolva `loja.html` para `/loja/*` e repasse `/api` para a API.

## Próximas etapas combinadas
1. Carrinho salvo no servidor + **oferta com prazo** ("compre em 30 min e ganhe X%") definida pelo lojista.
2. Aviso de **carrinho esquecido** (push/e-mail) usando a fila de push e o Resend que já existem.
3. QR code do link da loja (impressão/vitrine física) e metadados para compartilhar (Open Graph) com a foto da loja.
