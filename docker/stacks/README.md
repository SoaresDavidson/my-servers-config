# Stacks

Uma stack por serviço. Cada diretório tem:

- `docker-compose.yml` — sidecar Tailscale + aplicação (`network_mode: service:tailscale-<svc>`), mais o bloco `x-casaos` que define ícone, título e WebUI no dashboard do CasaOS.
- `ts-serve.json` — configuração do `tailscale serve`, apontando para a porta da aplicação em `127.0.0.1`.
- `.env` — symlink para `../../.env`, gerado por `../setup-env.sh`.

Todas as stacks entram na mesma rede Docker (`NETWORK_NAME`), declarada como `external`. A rede é criada pelo `setup-env.sh`.

## Uso

```sh
cd docker
./setup-env.sh              # cria .env, os symlinks, a rede e valida as stacks
./up.sh                     # sobe todas as stacks
./up.sh sonarr radarr       # sobe apenas as stacks nomeadas
./down.sh                   # derruba todas as stacks
./link-env.sh               # recria os symlinks .env (já chamado pelo setup-env)
```

Os scripts passam `--env-file ../../.env` explicitamente, então funcionam mesmo
sem os symlinks. Os symlinks existem para o uso manual:

```sh
cd stacks/sonarr
docker compose up -d        # lê o .env do próprio diretório do compose
```

## CasaOS

No CasaOS, use *Custom Install → Import*, colando o conteúdo de `docker-compose.yml` da stack. O `x-casaos` de topo define:

- `main` — o contêiner sidecar Tailscale, que é quem publica a porta no host. A aplicação em si não publica porta nenhuma.
- `port_map` — a porta publicada no host, usada para montar o link da WebUI.
- `icon` — ícone exibido no dashboard.

O bind `./ts-serve.json` é relativo ao diretório do compose. Instalando pelo CasaOS, copie o `ts-serve.json` da stack para o mesmo diretório onde o CasaOS grava o compose (`/var/lib/casaos/apps/<app>/`), ou troque o bind por um caminho absoluto.

## Serviços e portas

| Stack | Porta no host | Porta da aplicação |
| --- | --- | --- |
| sonarr | 8989 | 8989 |
| radarr | 7878 | 7878 |
| prowlarr | 9696 | 9696 |
| lidarr | 8686 | 8686 |
| bazarr | 6767 | 6767 |
| profilarr | 6868 | 6868 |
| qbittorrent | — (sem porta no host, atrás da Proton VPN) | 8080 |
| jellyfin | 8096 | 8096 |
| jellyseerr | 5055 | 5055 |
| shared (flaresolverr, decluttarr) | — | — |
