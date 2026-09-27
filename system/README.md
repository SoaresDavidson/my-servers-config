# system

Configurações do host (Debian 13) fora do Docker. Cada arquivo é copiado para o destino com `sudo install`; o comando exato está no comentário do topo de cada arquivo.

| Pasta | Arquivo | Destino no host | O que faz |
|---|---|---|---|
| `cron.d/` | `apt-update` | `/etc/cron.d/apt-update` | Roda `apt-get update` às 02:50 (antes do backup das 03:00) e grava os pacotes atualizáveis em `/var/lib/host-status/apt-upgradable.txt`, lido pelo hermes. |
| `apt.conf.d/` | `20auto-upgrades` | `/etc/apt/apt.conf.d/20auto-upgrades` | Liga o unattended-upgrades: atualiza as listas e instala atualizações todo dia, e limpa o cache de `.deb` a cada 7 dias. |
| `apt.conf.d/` | `52unattended-upgrades-local` | `/etc/apt/apt.conf.d/52unattended-upgrades-local` | Ajustes sobre o `50unattended-upgrades` do pacote: remove dependências e kernels antigos e reinicia às 04:30 só se existir `/var/run/reboot-required`. Docker, Tailscale e CUDA ficam manuais. |
| `systemd/apt-daily-upgrade.timer.d/` | `override.conf` | `/etc/systemd/system/apt-daily-upgrade.timer.d/override.conf` | Move o unattended-upgrades de ~06:00 para 04:00, depois do backup e antes do reboot das 04:30. Requer `systemctl daemon-reload`. |

## Horários da madrugada

| Hora | O quê | Origem |
|---|---|---|
| 02:50 | `apt-get update` + lista de pacotes atualizáveis | `cron.d/apt-update` |
| 03:00 | Backup (offen) | `docker/stacks/backup` |
| 04:00–04:10 | unattended-upgrades instala atualizações do Debian | `systemd/apt-daily-upgrade.timer.d/override.conf` |
| 04:30 | Reboot, só se alguma atualização exigir | `apt.conf.d/52unattended-upgrades-local` |
