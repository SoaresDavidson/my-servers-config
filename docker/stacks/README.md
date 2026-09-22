# Stacks

Uma stack por serviço. Cada diretório tem:

- `docker-compose.yml` — sidecar Tailscale + aplicação (`network_mode: service:tailscale-<svc>`), mais o bloco `x-casaos` que define ícone, título e WebUI no dashboard do CasaOS.
- `ts-serve.json` — configuração do `tailscale serve`, apontando para a porta da aplicação em `127.0.0.1`.
- `.env` — symlink para `../../.env`, gerado por `../setup-env.sh`.

O estado de autenticação do Tailscale fica em `${CONFIG_HOST_PATH}/tailscale/<serviço>`, como bind mount. Volume nomeado não é usado porque o formulário do CasaOS não sabe importá-lo.

Todas as stacks entram na mesma rede Docker (`NETWORK_NAME`), declarada como `external`. A rede é criada pelo `setup-env.sh`.

## Uso

```sh
cd docker
./setup-env.sh              # cria .env, cria a rede e valida todas as stacks
cd stacks/sonarr
docker compose up -d
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
| qbittorrent | 8080 (sem Tailscale, atrás da Proton VPN) | 8080 |
| jellyfin | 8096 | 8096 |
| jellyseerr | 5055 | 5055 |
| bookshelf (fork do Readarr) | 8787 | 8787 |
| calibre | 8082 (GUI), 8081 (content server) | 8080, 8081 |
| shelfarr | 5056 | 80 |
| questarr | 5000 | 5000 |
| shared (flaresolverr, decluttarr) | — | — |

## Layout de dados

Downloads e mídia entram nos containers como **um único mount**, `${DATA_HOST_PATH}:/data`:

```
/data
├── downloads          # destino do qBittorrent
└── media
    ├── tv             # root folder do Sonarr
    ├── movies         # root folder do Radarr
    ├── music          # root folder do Lidarr
    ├── books          # root folder do Bookshelf, biblioteca do Calibre, ebooks do Shelfarr
    └── audiobooks     # audiobooks do Shelfarr
```

Montar como um só mount é o que permite hardlink entre o download e a biblioteca. Com binds separados (`/downloads` e `/tv`), o `link()` falha com `EXDEV` mesmo estando no mesmo filesystem do host, e todo import vira cópia — dobrando o espaço em disco e quebrando o seeding.

Jellyfin, Bazarr e Calibre recebem só `${DATA_HOST_PATH}/media:/data/media`, já que não precisam enxergar os downloads.

Shelfarr é exceção: usa binds separados (`/downloads`, `/ebooks`, `/audiobooks`) porque a imagem espera esses caminhos e move o arquivo em vez de fazer hardlink.
