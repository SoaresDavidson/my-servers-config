# system

Configurações do host (Debian 13) fora do Docker. Cada arquivo é copiado para o destino com `sudo install`; o comando exato está no comentário do topo de cada arquivo.

| Pasta | Arquivo | Destino no host | O que faz |
|---|---|---|---|
| `cron.d/` | `apt-update` | `/etc/cron.d/apt-update` | Roda `apt-get update` às 02:50 (antes do backup das 03:00) e grava os pacotes atualizáveis em `/var/lib/host-status/apt-upgradable.txt`, lido pelo hermes. |
| `apt.conf.d/` | `20auto-upgrades` | `/etc/apt/apt.conf.d/20auto-upgrades` | Liga o unattended-upgrades: atualiza as listas e instala atualizações todo dia, e limpa o cache de `.deb` a cada 7 dias. |
| `apt.conf.d/` | `52unattended-upgrades-local` | `/etc/apt/apt.conf.d/52unattended-upgrades-local` | Ajustes sobre o `50unattended-upgrades` do pacote: remove dependências e kernels antigos e **não** reinicia sozinho (reboot manual quando houver `/var/run/reboot-required`). Docker, Tailscale e CUDA ficam manuais. |
| `systemd/apt-daily-upgrade.timer.d/` | `override.conf` | `/etc/systemd/system/apt-daily-upgrade.timer.d/override.conf` | Move o unattended-upgrades de ~06:00 para 04:00, depois do backup das 03:00. Requer `systemctl daemon-reload`. |
| `docker/` | `daemon.json` | `/etc/docker/daemon.json` | Expõe as métricas do dockerd na porta 9323. A chave é `metrics-addr`, com hífen: uma chave desconhecida, como `metrics_addr`, impede o dockerd de subir, e o erro só aparece no próximo restart. Valide com `sudo dockerd --validate` antes de reiniciar. |
| `systemd/docker.service.d/` | `override.conf` | `/etc/systemd/system/docker.service.d/override.conf` | Sobe o Docker depois de montar o HD de mídia (`/mnt/midia`). Requer `systemctl daemon-reload`. |
| `default/` | `hd-idle` | `/etc/default/hd-idle` | Para o HD de mídia depois de 20 min sem I/O. Requer o pacote `hd-idle`. |
| `systemd/powertop.service.d/` | `override.conf` | `/etc/systemd/system/powertop.service.d/override.conf` | Roda `powertop --auto-tune` no boot e depois `usb-keep-awake`. Requer `systemctl daemon-reload`. |
| `sbin/` | `usb-keep-awake` | `/usr/local/sbin/usb-keep-awake` | Tira do autosuspend USB o HD de mídia e o adaptador de rede do dock (RTL8153, reserva), que o powertop teria colocado para dormir. |
| `default/grub.d/` | `libata-noncq.cfg` | `/etc/default/grub.d/libata-noncq.cfg` | Desliga o NCQ do SSD interno, que trava sob carga com a fila em 32. Requer `sudo update-grub`. |
| `.` | `mbpfan.conf` | `/etc/mbpfan.conf` | Curva das ventoinhas, antecipada para reagir antes de a CPU esquentar. Requer o pacote `mbpfan`. |
| `sbin/` e `systemd/` | `mac-gpu-intel`, `mac-gpu-intel.service` | `/usr/local/sbin/mac-gpu-intel`, `/etc/systemd/system/mac-gpu-intel.service` | Desliga a NVIDIA no boot e deixa a tela na Intel. |
| `sbin/` e `systemd/` | `mac-prochot-off`, `mac-prochot-off.service` | `/usr/local/sbin/mac-prochot-off`, `/etc/systemd/system/mac-prochot-off.service` | Faz a CPU ignorar o PROCHOT externo, que a prende em 800 MHz, e desliga o turbo para limitar o calor. Requer o pacote `msr-tools`. |
| `sbin/` e `systemd/` | `mac-net-watchdog`, `mac-net-watchdog.service`, `mac-net-watchdog.timer` | `/usr/local/sbin/mac-net-watchdog`, `/etc/systemd/system/mac-net-watchdog.{service,timer}` | Traz de volta a rede do adaptador Thunderbolt (`ens9`) quando ela some: `ifup`, depois rescan do PCI e, por último, reboot (no máximo 2 seguidos). Roda 90 s após o boot e a cada 5 min. Ver [Rede](#rede). |
| `systemd/` | `hermes-gateway-471fd707.service` | `/etc/systemd/system/hermes-gateway-471fd707.service` | Gateway do Hermes Agent direto no host, com `User=davi`. Ver [Hermes](#hermes). |
| `systemd/user/` | `vagas-linkedin-consumer.service` | `~/.config/systemd/user/vagas-linkedin-consumer.service` | Consumidor Pub/Sub do Gmail em serviço de usuário com linger ativo. Ver [Vagas do LinkedIn](#vagas-do-linkedin). |
| `systemd/` | `vagas-linkedin-consumer.service` | `/etc/systemd/system/vagas-linkedin-consumer.service` | Alternativa de serviço de sistema, não habilitar simultaneamente ao serviço de usuário. |

## Hermes

O Hermes Agent saiu do Docker e roda no host: código em `~/hermes-agent` (instalado com `./setup-hermes.sh`,
comando em `~/.local/bin/hermes`) e dados em `HERMES_HOME=/DATA/AppData/media-stack/hermes/data`
(exportado no `~/.zshrc`). As credenciais do Discord e outras variáveis necessárias ao gateway
ficam em `$HERMES_HOME/.env` (fora do repo); a autenticação Codex fica no `auth.json` do Hermes.
Para ativar o dashboard fora do Docker, configure-o separadamente, considerando a exposição da porta 9119.

A unit é gerada pelo próprio Hermes e precisa ficar **idêntica** ao que ele gera: `hermes gateway status`
compara o arquivo instalado com o gerado e acusa "desatualizada" por qualquer diferença, até comentários.
Por isso o arquivo não tem o cabeçalho de instalação dos outros. O hash no nome também vem do Hermes.

```bash
sudo install -D -m 644 -o root -g root system/systemd/hermes-gateway-471fd707.service /etc/systemd/system/hermes-gateway-471fd707.service
sudo systemctl daemon-reload
sudo systemctl enable --now hermes-gateway-471fd707.service
journalctl -u hermes-gateway-471fd707 -f
```

Se o Hermes atualizar node/npm em `tools/` e o status acusar unit desatualizada, regenere com
`sudo HERMES_HOME=$HERMES_HOME hermes gateway install --system --run-as-user davi --force` e copie
`/etc/systemd/system/hermes-gateway-471fd707.service` de volta para cá.

A antiga stack Docker do Hermes foi removida. Mantenha apenas
um gateway ativo: se o serviço de usuário antigo estiver habilitado, desative-o com
`systemctl --user disable --now hermes-gateway.service` e confira o serviço de sistema com
`hermes gateway status --system`. Dois gateways no mesmo bot do Discord disputam as mensagens.

## Vagas do LinkedIn

O Gmail publica no tópico Pub/Sub `vagas-linkedin` (projeto `pub-sub-email`) quando um e-mail recebe a
etiqueta `vagas-linkedin`. O `vagas_linkedin_consumer.py` (em `$HERMES_HOME/scripts`, venv
`~/.venvs/vagas-linkedin`) consome a assinatura `vagas-linkedin-sub`, lê `users.history.list` desde o
cursor salvo e grava os IDs na fila `state/linkedin-vagas.sqlite3`; o ack só sai depois da gravação.
Renova o `users.watch` a cada 24h e relê o histórico a cada hora. Credenciais em `~/.config/vagas-linkedin/`
(fora do repo): `gmail-token.json` (OAuth, `gmail.readonly`) e `pubsub-sa.json` (só subscriber).
O job Hermes `f1cdc4faa83c` consulta apenas a fila a cada minuto e só ativa a IA quando ela muda;
entrega a resposta por DM no Discord. O primeiro `users.watch` cria o cursor sem reprocessar mensagens antigas.
Quando o histórico do Gmail expira (404), a recuperação varre apenas os e-mails dos últimos 7 dias na etiqueta.

O serviço de usuário está habilitado neste host (`loginctl show-user davi -p Linger` retorna `yes`).
Para reinstalar a unit versionada, sem habilitar a alternativa em `/etc/systemd/system`:

```bash
install -D -m 644 system/systemd/user/vagas-linkedin-consumer.service ~/.config/systemd/user/vagas-linkedin-consumer.service
systemctl --user daemon-reload
systemctl --user enable --now vagas-linkedin-consumer.service
journalctl --user -u vagas-linkedin-consumer -f
```

## Energia

O servidor é um MacBook Pro 15" (Mid 2014) sempre ligado. O suspend do sistema (`sleep`, `suspend` e
`hibernate.target`) fica mascarado e `HandleLidSwitch=ignore` no `logind.conf`, porque com a máquina
dormindo os serviços somem, inclusive o DNS do AdGuard. A economia vem de cada componente dormir sozinho:

- **CPU**: C-states (até C7s) e `schedutil`, sem configuração.
- **HD de mídia**: `hd-idle` (`default/hd-idle`). Não para enquanto houver torrent semeando.
- **USB/SATA/PCIe/áudio**: `powertop --auto-tune` (`systemd/powertop.service.d/`), exceto HD e rede USB reserva. A rede principal (`ens9`, Thunderbolt) é PCIe e não entra no autosuspend USB.
- **Ventoinhas**: `mbpfan` controla as ventoinhas pela temperatura (módulos `applesmc` e `coretemp`).
  A curva fica em `mbpfan.conf`, antecipada para acelerar a partir de 55 °C e chegar ao máximo em 80 °C:
  `sudo apt install mbpfan && sudo systemctl enable --now mbpfan`.
- **GPU**: a NVIDIA fica desligada (`sbin/mac-gpu-intel`), e a Intel, que depende do `apple_set_os.efi` na entrada `Boot0005`, serve a tela e o VA-API do Jellyfin.
- **CPU presa em 800 MHz**: um PROCHOT externo de origem desconhecida limita a CPU (`sbin/mac-prochot-off`). Se o servidor ficar lento, meça a frequência sob carga, não em repouso.

Se trocar o adaptador de rede ou o HD, atualize os IDs em `sbin/usb-keep-awake` (`lsusb`) e o caminho
by-id em `default/hd-idle` (`ls /dev/disk/by-id/`).

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

## Rede

A única rede é o adaptador Apple Thunderbolt→Gigabit (`ens9`, tg3, IP `.35` por reserva de DHCP no roteador).
No Linux, o Thunderbolt do Mac às vezes falha ao ler a DROM do adaptador no boot (`reading DROM failed`,
`failed to initialize port 1`): o adaptador aparece em `/sys/bus/thunderbolt`, mas a placa PCIe dentro dele
não, e o servidor fica sem rede nenhuma, Tailscale incluído. Foi o que aconteceu em 09/11/2026, depois do reboot
automático das 04:30. Por isso o reboot automático do unattended-upgrades está desligado.

Recuperação manual, no console: `echo 1 > /sys/bus/pci/rescan`, depois `ifdown --force ens9; ifup ens9`.
O `mac-net-watchdog` faz isso sozinho. Histórico: `journalctl -u mac-net-watchdog`.

```bash
sudo install -m 755 -o root -g root system/sbin/mac-net-watchdog /usr/local/sbin/mac-net-watchdog
sudo install -D -m 644 -o root -g root system/systemd/mac-net-watchdog.service /etc/systemd/system/mac-net-watchdog.service
sudo install -D -m 644 -o root -g root system/systemd/mac-net-watchdog.timer /etc/systemd/system/mac-net-watchdog.timer
sudo systemctl daemon-reload && sudo systemctl enable --now mac-net-watchdog.timer
```

## Horários da madrugada

| Hora | O quê | Origem |
|---|---|---|
| 02:50 | `apt-get update` + lista de pacotes atualizáveis | `cron.d/apt-update` |
| 03:00 | Backup (offen) | `docker/server/backup` |
| 04:00–04:10 | unattended-upgrades instala atualizações do Debian | `systemd/apt-daily-upgrade.timer.d/override.conf` |
