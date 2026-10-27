# Fotos dos produtos no Cloudflare R2

Mesmo esquema do Gerenciamento Max. A equipe tira/escolhe a foto no app; a API:
1. confere que é **JPG ou PNG pelo conteúdo** (não pela extensão) e recusa acima de 50 megapixels;
2. reduz para no máximo 1600 px (e gera a miniatura de 480 px da vitrine), corrige a orientação da câmera e
   recomprime em JPEG — os dados EXIF (inclusive GPS) não vão junto;
3. grava no R2 com nome aleatório (`produtos/<id>/<uuid>.jpg` e `-p.jpg`) e cache de 1 ano. Se o pedido falhar,
   os arquivos são apagados; ao apagar a foto (ou o produto), os arquivos saem do R2 depois do commit.

Sem as cinco variáveis do R2, as fotos vão para o disco (`APP_MEDIA_PATH`, volume `media` no compose) e são servidas
em `/api/public/media/**`. Limites: `APP_MEDIA_MAX_UPLOAD_MB` (15) e `APP_MEDIA_MAX_PHOTOS` por produto (8).

## Configurar
1. Cloudflare → **R2** → *Create bucket* (ex.: `loja-max-fotos`).
2. No bucket → *Settings → Public access* → ligue o **r2.dev** (ou ligue um domínio próprio). Esse endereço é o
   `R2_PUBLIC_BASE_URL`.
3. R2 → *Manage R2 API Tokens* → **Create API token** com permissão *Object Read & Write* **só nesse bucket**.
   Copie `Access Key ID` e `Secret Access Key`.
4. No `.env` do servidor:
   ```
   R2_BUCKET=loja-max-fotos
   R2_ENDPOINT=https://<ACCOUNT_ID>.r2.cloudflarestorage.com
   R2_ACCESS_KEY_ID=...
   R2_SECRET_ACCESS_KEY=...
   R2_PUBLIC_BASE_URL=https://pub-xxxx.r2.dev
   ```
   Reinicie a API; o log mostra `Fotos dos produtos: Cloudflare R2 (loja-max-fotos)`.
