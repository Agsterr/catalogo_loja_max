#!/usr/bin/env bash
# Guardião do disco do servidor (todos os apps). Roda todo dia pelo cron; veja deploy/ops/README.md.
# Sempre: encolhe o diário do systemd, tira imagens "soltas" e cache de build com mais de 3 dias.
# Se o disco passar de LIMIT% (padrão 75): também apaga cache de build inteiro e imagens SEM container
# (nem parado) criadas há mais de 14 dias, exceto tags rollback-* (volta rápida de deploy).
# Nunca mexe em volumes (bancos, fotos, backups) nem em imagem de container existente.
# Uso: bash disk-guard.sh [--dry-run]
set -uo pipefail

LIMIT="${LIMIT:-75}"
JOURNAL_MAX="${JOURNAL_MAX:-300M}"
DRY=false
[[ "${1:-}" == "--dry-run" ]] && DRY=true

used() { df / | awk 'NR==2 {gsub("%","",$5); print $5}'; }
show() { df -h / | awk 'NR==2 {print $3 " usados, " $4 " livres (" $5 ")"}'; }
run() { if $DRY; then echo "(simulação) $*"; else "$@" >/dev/null 2>&1; fi; }

echo "==> $(date '+%F %T') disco antes: $(show)"

run journalctl --vacuum-size="$JOURNAL_MAX"
run docker image prune -f
run docker builder prune -f --filter "until=72h"

if (( $(used) >= LIMIT )) || $DRY; then
  echo "==> disco >= ${LIMIT}%: limpeza reforçada"
  run docker builder prune -af
  # imagens sem nenhum container, com mais de 14 dias, fora as rollback-*
  mapfile -t in_use < <(docker ps -aq | xargs -r docker inspect -f '{{.Image}}' | sort -u)
  cutoff=$(date -d '14 days ago' +%s)
  while IFS='|' read -r id ref created; do
    [[ "$ref" == *"<none>"* || "$ref" == *":rollback-"* ]] && continue
    printf '%s\n' "${in_use[@]}" | grep -qxF "$id" && continue
    (( $(date -d "$created" +%s 2>/dev/null || echo "$cutoff") < cutoff )) || continue
    if $DRY; then echo "apagaria $ref"; else docker rmi "$ref" >/dev/null 2>&1 && echo "apagada $ref" || echo "mantida $ref"; fi
  done < <(docker images --no-trunc --format '{{.ID}}|{{.Repository}}:{{.Tag}}|{{.CreatedAt}}')
fi

after=$(used)
echo "==> disco depois: $(show)"
if (( after >= 90 )); then
  echo "ALERTA: disco em ${after}% mesmo depois da limpeza; veja 'docker system df' e 'du -xh /var --max-depth=2'"
  exit 2
fi
