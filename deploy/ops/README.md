# Operação do servidor

## Limpeza automática do disco (`disk-guard.sh`)
Serve todos os apps do servidor Hetzner. Instalado em `/usr/local/sbin/disk-guard.sh`, roda **todo dia às 05:00** pelo cron
do root e escreve em `/var/log/disk-guard.log`.

- Sempre: encolhe o diário do systemd (300 MB), apaga imagens soltas e cache de build com mais de 3 dias.
- Disco em 75% ou mais: apaga todo o cache de build e imagens sem nenhum container (nem parado) criadas há mais de 14 dias,
  menos as `rollback-*`. Imagem de container existente e volumes (bancos, fotos, backups) nunca são tocados.
- Disco ainda em 90% ou mais depois da limpeza: sai com código 2 e registra `ALERTA` no log.
- `LIMIT`, `JOURNAL_MAX` e `--dry-run` ajustam/simulam: `LIMIT=60 bash disk-guard.sh --dry-run`.

Atualizar no servidor: `scp deploy/ops/disk-guard.sh hetzner:/usr/local/sbin/ && ssh hetzner chmod 755 /usr/local/sbin/disk-guard.sh`.
Teste em 29/10/2026: disco de 95% para 65% (cache de build, diário e imagens) com os 38 containers no ar.
O `docker-cleanup.sh` semanal do Salão Max continua (mantém as 4 últimas imagens dele).
