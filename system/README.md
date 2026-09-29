# system

Configurações do host (Debian 13) fora do Docker. Cada arquivo é copiado para o destino com `sudo install`; o comando exato está no comentário do topo de cada arquivo.

| Pasta | Arquivo | Destino no host | O que faz |
|---|---|---|---|
| `cron.d/` | `apt-update` | `/etc/cron.d/apt-update` | Roda `apt-get update` às 02:50 (antes do backup das 03:00) e grava os pacotes atualizáveis em `/var/lib/host-status/apt-upgradable.txt`, lido pelo hermes. |
| `apt.conf.d/` | `20auto-upgrades` | `/etc/apt/apt.conf.d/20auto-upgrades` | Liga o unattended-upgrades: atualiza as listas e instala atualizações todo dia, e limpa o cache de `.deb` a cada 7 dias. |
| `apt.conf.d/` | `52unattended-upgrades-local` | `/etc/apt/apt.conf.d/52unattended-upgrades-local` | Ajustes sobre o `50unattended-upgrades` do pacote: remove dependências e kernels antigos e reinicia às 04:30 só se existir `/var/run/reboot-required`. Docker, Tailscale e CUDA ficam manuais. |
| `systemd/apt-daily-upgrade.timer.d/` | `override.conf` | `/etc/systemd/system/apt-daily-upgrade.timer.d/override.conf` | Move o unattended-upgrades de ~06:00 para 04:00, depois do backup e antes do reboot das 04:30. Requer `systemctl daemon-reload`. |
| `systemd/docker.service.d/` | `override.conf` | `/etc/systemd/system/docker.service.d/override.conf` | Sobe o Docker depois de montar o HD de mídia (`/mnt/midia`). Requer `systemctl daemon-reload`. |

## HD de mídia

Downloads e bibliotecas (`DATA_HOST_PATH`) ficam num HD dedicado montado em `/mnt/midia`. Linha no `/etc/fstab`:

```
UUID=25e0f546-4401-4cb2-b3f4-997cac46ab09 /mnt/midia ext4 defaults,nofail 0 2
```

`nofail` deixa o boot seguir se o HD falhar, mas aí `/mnt/midia` vira uma pasta vazia no SSD e os containers
gravariam nela. Para impedir isso, o ponto de montagem (com o HD desmontado) fica imutável:

```bash
sudo umount /mnt/midia && sudo chattr +i /mnt/midia && sudo mount /mnt/midia
```

`Downloads/` e `media/` precisam estar no mesmo HD para os *arr fazerem hardlink. Para migrar entre discos,
use `rsync -aH` (um `cp`/`mv` comum desfaz os hardlinks e duplica o espaço).

## Horários da madrugada

| Hora | O quê | Origem |
|---|---|---|
| 02:50 | `apt-get update` + lista de pacotes atualizáveis | `cron.d/apt-update` |
| 03:00 | Backup (offen) | `docker/stacks/backup` |
| 04:00–04:10 | unattended-upgrades instala atualizações do Debian | `systemd/apt-daily-upgrade.timer.d/override.conf` |
| 04:30 | Reboot, só se alguma atualização exigir | `apt.conf.d/52unattended-upgrades-local` |
