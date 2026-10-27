#!/usr/bin/env bash
# Roda no servidor (chamado pelo GitHub Actions): gera as páginas públicas, baixa a imagem nova e reinicia.
# Uso: API_IMAGE=... bash /opt/loja-max/deploy.sh
set -euo pipefail
trap '' HUP

APP_DIR="${APP_DIR:-/opt/loja-max}"
cd "$APP_DIR"

if [[ ! -f .env ]]; then
  echo "ERRO: ${APP_DIR}/.env ausente (modelo: deploy/.env.production.example)"
  exit 1
fi

export COMPOSE_FILE=docker-compose.prod.yml
export COMPOSE_PARALLEL_LIMIT=1

echo "==> Páginas públicas (privacidade, termos, excluir conta)"
LEGAL_COMPANY=$(grep -E '^LEGAL_COMPANY=' .env | cut -d= -f2- | tr -d '"' || true)
LEGAL_EMAIL=$(grep -E '^LEGAL_EMAIL=' .env | cut -d= -f2- | tr -d '"' || true)
LEGAL_COMPANY=${LEGAL_COMPANY:-Loja Max}
LEGAL_EMAIL=${LEGAL_EMAIL:-contato@lojamax.com.br}
TODAY=$(date +%d/%m/%Y)
rm -rf site-public && mkdir -p site-public
for f in site/*; do
  sed -e "s|__EMPRESA__|${LEGAL_COMPANY}|g" -e "s|__EMAIL__|${LEGAL_EMAIL}|g" -e "s|__DATA__|${TODAY}|g" "$f" \
    > "site-public/$(basename "$f")"
done

echo "==> Pull da imagem"
docker compose pull api

echo "==> Banco"
docker compose up -d db

echo "==> API, backup e nginx"
docker compose up -d --remove-orphans

echo "==> Aguardando a API"
for i in $(seq 1 40); do
  if docker compose exec -T nginx wget -qO- http://api:8080/actuator/health 2>/dev/null | grep -q '"UP"'; then
    echo "API no ar."
    break
  fi
  if [[ "$i" -eq 40 ]]; then
    echo "API não respondeu em 200s. Últimos logs:"
    docker compose logs --tail=80 api
    exit 1
  fi
  sleep 5
done

docker image prune -f >/dev/null
docker ps --filter name=loja-max --format 'table {{.Names}}\t{{.Status}}'
echo "Deploy concluído em $(date -u +'%Y-%m-%dT%H:%M:%SZ')."
