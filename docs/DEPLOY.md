# Publicação (deploy) — Loja Max

Mesmo esquema do Gerenciamento Max: o GitHub builda a imagem da API e o servidor (Hetzner) só baixa e reinicia.

```
push na main (backend/ ou deploy/) → testes da API → imagem ghcr.io/agsterr/loja-max-api → servidor: pull + restart
```

O mesmo servidor serve as **páginas públicas** que as lojas de apps pedem: `/` (início), `/privacidade`, `/termos` e
`/excluir-conta`, com o nome da empresa e o e-mail de contato do `.env` (`LEGAL_COMPANY`, `LEGAL_EMAIL`).

## Uma vez só

### 1. Servidor
Pode ser o mesmo do Gerenciamento (a API usa ~450 MB de RAM; porta local `8090`, a do Gerenciamento é `8089`).

```bash
ssh root@SEU_SERVIDOR
mkdir -p /opt/loja-max && cd /opt/loja-max
nano .env        # copie o modelo deploy/.env.production.example e preencha
chmod 600 .env
```

Gere os segredos com `openssl rand -base64 48` (`JWT_SECRET`, `APP_ENCRYPTION_KEY`) e `openssl rand -base64 24`
(`POSTGRES_PASSWORD`). Senha do admin da plataforma: 12+ caracteres.

### 2. Domínio (Cloudflare)
No túnel Cloudflare do servidor, adicione o hostname (ex.: `lojamax.focodev.com.br`) apontando para
`http://localhost:8090`. É o mesmo procedimento do Gerenciamento (`deploy/cloudflare-hostname.sh` de lá).
O HTTPS fica com o Cloudflare.

### 3. GitHub → *Settings → Secrets and variables → Actions*
| Tipo | Nome | Valor |
|---|---|---|
| Secret | `HETZNER_HOST` | IP ou host do servidor |
| Secret | `HETZNER_SSH_KEY` | chave privada SSH que entra no servidor |
| Secret | `HETZNER_USER` | usuário SSH (opcional, padrão `root`) |
| Variable | `PUBLIC_URL` | `https://lojamax.focodev.com.br` (ou o seu domínio) |
| Variable | `API_URL` | o mesmo endereço (usado no build dos apps) |
| Secret | `FIREBASE_*` | veja [PUSH.md](PUSH.md) |

Sem `HETZNER_*` o workflow publica só a imagem e avisa; nada quebra.

### 4. Branch `main`
O deploy roda em push na `main`. Mescle o branch de trabalho (ou abra um PR e mescle). Também dá para rodar à mão:
*Actions → Deploy (servidor) → Run workflow*.

## Dia a dia
- Logs: `ssh SERVIDOR "cd /opt/loja-max && docker compose -f docker-compose.prod.yml logs -f api"`
- Deploy manual: `ssh SERVIDOR "cd /opt/loja-max && API_IMAGE=ghcr.io/agsterr/loja-max-api:latest bash deploy.sh"`
- Saúde: `curl https://SEU_DOMINIO/actuator/health`

## Backup do banco
O serviço `backup` faz `pg_dump` ao subir e a cada 24 h (últimos `BACKUP_KEEP_DAYS`, padrão 14, no volume
`db_backups`). Para guardar fora do servidor, crie um bucket **privado** no R2 e coloque `BACKUP_BUCKET` no `.env`.

Restaurar (banco vazio, API parada):
```bash
cd /opt/loja-max && export COMPOSE_FILE=docker-compose.prod.yml
docker compose stop api
docker run --rm -v loja-max_db_backups:/b alpine ls /b
docker run --rm -v loja-max_db_backups:/b alpine cat /b/loja-AAAA-MM-DD-HHMM.sql.gz | gunzip | docker compose exec -T db psql -U loja loja
docker compose start api
```

## Testado
O compose de produção foi subido localmente com a imagem da API: saúde, páginas públicas (com nome/e-mail do
`.env`), cadastro de loja, produto, foto gravada e servida, login do admin e backup do banco funcionaram.
