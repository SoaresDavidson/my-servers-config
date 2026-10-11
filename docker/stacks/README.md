# Stacks

Uma stack por serviço (exceto `shared` e `backup`, ver abaixo). Cada diretório tem:

- `docker-compose.yml` — sidecar Tailscale + aplicação (`network_mode: service:tailscale-<svc>`), mais o bloco `x-casaos` que define ícone, título e WebUI no dashboard do CasaOS.
- `ts-serve.json` — configuração do `tailscale serve`, apontando para a porta da aplicação em `127.0.0.1`.
- `.env` — symlink para `../../.env`, gerado por `scripts/setup-env.sh`.

O estado de autenticação do Tailscale fica em `${CONFIG_HOST_PATH}/tailscale/<serviço>`, como bind mount. Volume nomeado não é usado porque o formulário do CasaOS não sabe importá-lo.

Todas as stacks entram na mesma rede Docker (`NETWORK_NAME`), declarada como `external`. A rede é criada pelo `scripts/setup-env.sh`.

Se a sidecar reinicia depois do app (boot lento, por exemplo), o app fica preso num network namespace órfão, só com `lo`, e para de responder pela LAN e pelo tailnet. Por isso o healthcheck de cada app começa com `test -e /sys/class/net/eth0`, e o label `autoheal=true` deixa o `autoheal` (stack `shared`) reiniciar o app, que volta já no namespace atual da sidecar. A imagem do dozzle é `scratch` (sem shell), então o healthcheck dela é só `/dozzle healthcheck` e não detecta o namespace órfão; se o dozzle sumir da rede depois de um reinício da sidecar, reinicie-o à mão. (Montar o busybox via volume `type: image` funcionaria, mas o CasaOS não consegue validar esse compose e o painel passa a mostrar "failed to load apps".)

## Uso

```sh
# A partir da raiz do repositório:
./scripts/setup-env.sh      # cria .env, cria a rede e valida todas as stacks
./scripts/up-all.sh         # sobe todas as stacks
./scripts/update-all.sh     # baixa imagens novas e atualiza todas as stacks
./scripts/down-all.sh       # derruba todas as stacks

# Para operar apenas uma stack:
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
| calibre | 8082 (GUI), 8081 (content server), 9090 (dispositivo sem fio) | 8080, 8081, 9090 |
| shelfarr | 5056 | 80 |
| lazylibrarian | 5299 | 5299 |
| koinsight (estatísticas do KOReader) | 3001 | 3000 |
| leituras (estatísticas do KOReader, build do GitHub) | 3333 no `HOST_LAN_IP` | 3333 |
| bookrats (leitura compartilhada, build do GitHub) | — (só Tailscale Funnel, público) | 8000 em loopback |
| kosync (KOReader Sync Server oficial; o bookrats repassa os PUTs) | — (rede Docker e tailnet) | 17200 (HTTP), 7200 (HTTPS autoassinado) |
| questarr | 5000 | 5000 |
| hermes (Hermes Agent) | 9119 (dashboard), 8642 (API) | 9119, 8642 |
| nextcloud (Postgres e Redis em 127.0.0.1, no namespace da sidecar) | 7580 | 80 |
| onlyoffice (editor de documentos do Nextcloud) | — (tailnet e rede Docker) | 80 |
| homepage (dashboard dos apps) | 3000 | 3000 |
| dozzle (logs dos containers) | 8888 | 8080 |
| adguard (DNS com bloqueio de anúncios) | 3080 (web), 53 tcp/udp no `HOST_LAN_IP` (DNS) | 80, 53 |
| shared (flaresolverr, decluttarr, autoheal) | — | — |
| clamav (antivírus dos downloads) | — | — |
| backup (offen/docker-volume-backup, rclone) | — | — |

## Backup

A stack `backup` faz, todo dia às 03:00, um `.tar.zst` criptografado com GPG de `${CONFIG_HOST_PATH}`
inteiro mais o `docker/.env`. Guarda uma cópia em `${BACKUP_HOST_PATH}` e envia outra ao Google Drive,
na pasta `media-stack-backups`. Mantém `${BACKUP_RETENTION_DAYS}` dias nos dois lugares.

Durante o backup, os containers com o label `docker-volume-backup.stop-during-backup=true` (as aplicações,
não os sidecars Tailscale) ficam parados, para os bancos SQLite serem copiados consistentes.

O offen só envia para o Drive via service account, que não tem cota em contas Gmail pessoais. Por isso ele
envia via WebDAV para o container `rclone`, que grava no Drive com OAuth da própria conta.

### Configuração inicial

1. Defina `BACKUP_PASSPHRASE` no `docker/.env` e guarde a senha também fora do servidor.
2. Crie o remote `gdrive` do rclone (uma vez). O servidor não tem navegador, então na hora de autenticar
   responda `n` para *Use web browser* e rode o `rclone authorize` que ele indicar num computador com navegador:

   ```sh
   docker run --rm -it -v /DATA/AppData/media-stack/rclone:/config/rclone rclone/rclone config
   # n (new remote) -> name: gdrive -> storage: drive -> client_id/secret: vazio
   # scope: drive.file (o rclone só enxerga os arquivos que ele mesmo criou)
   ```
3. Suba a stack e dispare um backup manual para testar:

   ```sh
   docker compose -f stacks/backup/docker-compose.yml up -d
   docker exec backup backup
   ```

### Restaurar

```sh
gpg -d media-stack-<data>.tar.zst.gpg | zstd -d | tar -x
# backup/media-stack/<serviço>/ -> ${CONFIG_HOST_PATH}/<serviço>/   (com o container parado)
# backup/env/.env               -> docker/.env
```

## KOSync (progresso do KOReader)

O KOReader de todo mundo continua apontando para o bookrats (`https://bookrats.<tailnet>.ts.net`, pelo Funnel).
O bookrats grava cada `PUT /syncs/progress` no SQLite dele e repassa o corpo para o kosync oficial
(`BOOKRATS_KOSYNC_UPSTREAM=http://kosync_tailscale:17200`). Os `GET` leem do kosync primeiro e voltam para a
cópia local se ele estiver fora ou não conhecer o documento. Se o repasse falhar, o KOReader não vê erro; o
log do bookrats mostra `kosync upstream ...` (um 401 indica conta faltando no kosync).

O registro fica desligado (`ENABLE_USER_REGISTRATION=false`). A conta no kosync precisa ter o mesmo usuário e
a mesma chave (MD5 da senha) de `users.kosync_*` no bookrats. Crie direto no Redis, no **db 1** (o db do
ambiente `production`):

```sh
key=$(docker exec bookrats python -c "import sqlite3;print(sqlite3.connect('/data/bookrats.db').execute(\"select kosync_key from users where kosync_username='<usuario>'\").fetchone()[0])")
docker exec kosync redis-cli -n 1 SETNX user:<usuario>:key "$key"
```

O Calibre não fala kosync. Para levar progresso e anotações ao Calibre, use o plugin KOReader Sync com o
Kindle conectado como dispositivo sem fio (porta 9090 da stack `calibre`).

## Nextcloud e OnlyOffice

Migrados do CasaOS (`/DATA/AppData/big-bear-*`, que ficou intacto) para `${CONFIG_HOST_PATH}/nextcloud` e
`${CONFIG_HOST_PATH}/onlyoffice`. O `config.php` teve só o `dbhost` trocado para `127.0.0.1`.

O Nextcloud responde em três endereços: `https://nextcloud.<tailnet>.ts.net` (tailscale serve), `http://<HOST_LAN_IP>:7580`
e `http://tailscale-nextcloud` (rede Docker, usado pelo OnlyOffice). Entre as stacks, use o nome do serviço
(`tailscale-nextcloud`, `tailscale-onlyoffice`), não o `container_name`: o `_` não vale em hostname e o cliente HTTP
do Nextcloud o codifica (`onlyoffice%5ftailscale`), quebrando a conversão. `OVERWRITECONDADDR=^127\.0\.0\.1$` faz o https e o
host do tailnet valerem só para o que chega pelo tailscale serve; os outros dois seguem em http. O que a imagem só grava
na instalação (trusted domains, cron, app onlyoffice) é reaplicado a cada start por `hooks/10-config.sh`.

O editor abre no navegador em `https://onlyoffice.<tailnet>.ts.net`, então só funciona para quem está no tailnet. Na LAN
os arquivos abrem, mas a edição não. O segredo JWT (`ONLYOFFICE_JWT_SECRET`) é o mesmo nas duas stacks.

As imagens têm major fixo (`nextcloud:33-apache`, `postgres:14`): o Nextcloud não pula majors e o Postgres não abre
dados de outro major sem `pg_upgrade`. Para subir de major, troque a tag à mão, um major por vez.

## Proteção contra malware nos downloads

Quatro camadas, da mais barata à mais cara:

1. **qBittorrent** — `scripts/qbittorrent-exclusions.sh` grava via WebAPI a lista de *Excluded file names*:
   atalhos, protetores de tela e scripts do Windows Script Host (`.lnk`, `.url`, `.scr`, `.vbs`...), que não
   têm uso legítimo. A lista vale para todas as categorias, então `.exe` e compactados não entram por causa
   da categoria `game` (Questarr).
2. **Decluttarr** (stack `shared`) — nas categorias dos *arr, `REMOVE_BAD_FILES` desmarca no qBittorrent
   tudo que não é mídia (inclusive `.exe` e `.rar`) e manda o release para a blocklist; `REMOVE_FAILED_IMPORTS`
   remove o que o *arr recusou importar, como "Found executable file".
3. **ClamAV** (stack `clamav`) — `clamscan` de hora em hora nos arquivos de `/data` com ctime novo, e completo
   a cada 7 dias. Vídeo, áudio, legenda e imagem ficam de fora. Montado `:ro`: só reporta. Achados aparecem no
   log do container (Dozzle, procure `ALERTA`) e em `${CONFIG_HOST_PATH}/clamav/infected.log`.
   Arquivos acima de 2 GiB não são escaneados (limite do ClamAV).
4. **Isolamento** — containers sem root (`PUID`/`PGID`), Jellyfin com a biblioteca `:ro`, qBittorrent atrás
   da VPN. Nada baixado é executado no servidor; jogos, só depois de checar o hash no VirusTotal e de preferência
   numa VM.

## Layout de dados

No host, os downloads ficam em `/mnt/midia/Downloads` e as mídias em `/mnt/midia/media`, num HD dedicado.
Os containers que precisam criar hardlinks recebem o pai comum como **um único mount**,
`${DATA_HOST_PATH}:/data` (com `DATA_HOST_PATH=/mnt/midia`):

```
/data
├── Downloads          # destino do qBittorrent
└── media
    ├── tv             # root folder do Sonarr
    ├── movies         # root folder do Radarr
    ├── music          # root folder do Lidarr
    ├── books          # biblioteca do Calibre e root folder do Bookshelf
    │   └── inbox      # saida do Shelfarr e do LazyLibrarian; Calibre importa daqui (Automatic adding)
    └── audiobooks     # audiobooks do Shelfarr
```

No qBittorrent, configure o caminho padrão de salvamento como `/data/Downloads`. Nos apps
*arr, use `/data/Downloads` para downloads e `/data/media/<biblioteca>` para as root folders.
Esses caminhos correspondem, respectivamente, a `/mnt/midia/Downloads` e `/mnt/midia/media` no host.

Montar como um só mount é o que permite hardlink entre o download e a biblioteca. Com binds separados (`/downloads` e `/tv`), o `link()` falha com `EXDEV` mesmo estando no mesmo filesystem do host, e todo import vira cópia — dobrando o espaço em disco e quebrando o seeding.

Jellyfin, Bazarr e Calibre recebem só `${DATA_HOST_PATH}/media:/data/media`, já que não precisam enxergar os downloads.
No Jellyfin o mount é `:ro`; por isso as bibliotecas estão com *salvar metadados* e *salvar legendas junto da mídia*
desligados, e isso fica em `/config`.

Shelfarr é exceção: usa binds separados (`/downloads`, `/ebooks`, `/audiobooks`) porque a imagem espera esses caminhos e move o arquivo em vez de fazer hardlink.
