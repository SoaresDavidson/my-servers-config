# system

Configurações do host (Debian 13) fora do Docker. Cada arquivo é copiado para o destino com `sudo install`; o comando exato está no comentário do topo de cada arquivo.

| Pasta | Arquivo | Destino no host | O que faz |
|---|---|---|---|
| `cron.d/` | `apt-update` | `/etc/cron.d/apt-update` | Roda `apt-get update` às 02:50 (antes do backup das 03:00) e grava os pacotes atualizáveis em `/var/lib/host-status/apt-upgradable.txt`, lido pelo hermes. |
| `apt.conf.d/` | `20auto-upgrades` | `/etc/apt/apt.conf.d/20auto-upgrades` | Liga o unattended-upgrades: atualiza as listas e instala atualizações todo dia, e limpa o cache de `.deb` a cada 7 dias. |
| `apt.conf.d/` | `52unattended-upgrades-local` | `/etc/apt/apt.conf.d/52unattended-upgrades-local` | Ajustes sobre o `50unattended-upgrades` do pacote: remove dependências e kernels antigos e reinicia às 04:30 só se existir `/var/run/reboot-required`. Docker, Tailscale e CUDA ficam manuais. |
| `systemd/apt-daily-upgrade.timer.d/` | `override.conf` | `/etc/systemd/system/apt-daily-upgrade.timer.d/override.conf` | Move o unattended-upgrades de ~06:00 para 04:00, depois do backup e antes do reboot das 04:30. Requer `systemctl daemon-reload`. |
| `systemd/docker.service.d/` | `override.conf` | `/etc/systemd/system/docker.service.d/override.conf` | Sobe o Docker depois de montar o HD de mídia (`/mnt/midia`). Requer `systemctl daemon-reload`. |
| `default/` | `hd-idle` | `/etc/default/hd-idle` | Para o HD de mídia depois de 20 min sem I/O. Requer o pacote `hd-idle`. |
| `systemd/powertop.service.d/` | `override.conf` | `/etc/systemd/system/powertop.service.d/override.conf` | Roda `powertop --auto-tune` no boot e depois `usb-keep-awake`. Requer `systemctl daemon-reload`. |
| `sbin/` | `usb-keep-awake` | `/usr/local/sbin/usb-keep-awake` | Tira do autosuspend USB o HD de mídia e o adaptador de rede do dock (RTL8153, reserva), que o powertop teria colocado para dormir. |
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

O `scripts/up-all.sh` ignora a stack `docker/stacks/hermes`; não a suba manualmente. Mantenha apenas
um gateway ativo: se o serviço de usuário antigo estiver habilitado, desative-o com
`systemctl --user disable --now hermes-gateway-471fd707.service` e confira o serviço de sistema com
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
  Usa o `/etc/mbpfan.conf` padrão do pacote: `sudo apt install mbpfan && sudo systemctl enable --now mbpfan`.

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

## Horários da madrugada

| Hora | O quê | Origem |
|---|---|---|
| 02:50 | `apt-get update` + lista de pacotes atualizáveis | `cron.d/apt-update` |
| 03:00 | Backup (offen) | `docker/stacks/backup` |
| 04:00–04:10 | unattended-upgrades instala atualizações do Debian | `systemd/apt-daily-upgrade.timer.d/override.conf` |
| 04:30 | Reboot, só se alguma atualização exigir | `apt.conf.d/52unattended-upgrades-local` |
