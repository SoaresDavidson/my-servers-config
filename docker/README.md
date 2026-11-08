# Stacks Docker

Uma stack por serviço (exceto `shared` e `backup`, ver abaixo), agrupadas por assunto:

| Grupo | Stacks |
| --- | --- |
| `media/` | jellyfin, jellyseerr, sonarr, radarr, lidarr, prowlarr, bazarr, profilarr, qbittorrent, questarr |
| `books/` | calibre, bookshelf, shelfarr, lazylibrarian, kosync |
| `server/` | shared, adguard, backup, prometheus, dozzle, homepage, clamav |
| `apps/` | nextcloud (com o onlyoffice), falaai |

O nome da pasta da stack (não o do grupo) continua sendo o nome do projeto no Compose, então mover uma
stack de grupo não muda os nomes dos containers. Os grupos ficam direto em `docker/` e os scripts percorrem `docker/*/*/`. Em geral, cada diretório tem:

- `docker-compose.yml` — sidecar Tailscale + aplicação (`network_mode: service:tailscale-<svc>`).
- `ts-serve.json` — configuração do `tailscale serve`, apontando para a porta da aplicação em `127.0.0.1`.
- `.env` — symlink para `../../.env`, gerado por `scripts/setup-env.sh`.

O estado de autenticação do Tailscale fica em `${CONFIG_HOST_PATH}/tailscale/<serviço>`, como bind mount, para entrar no backup junto com o resto da config.

A stack `prometheus` não usa sidecar Tailscale: publica a porta 9091 somente no
`HOST_LAN_IP` (obrigatório), pois a 9090 já é usada pelo Calibre. A configuração fica em `server/prometheus/prometheus.yml`,
coletando as métricas do próprio Prometheus e do host. As do host vêm do `node-exporter`,
que roda na rede do host e escuta em `HOST_LAN_IP:9100`. Ele cobre CPU e frequência,
temperaturas e ventoinhas (`coretemp`/`applesmc`), latência dos discos, rede e o estado dos
serviços systemd da máquina (`mac-*`, `mbpfan`, `hd-idle`...). Os dados persistem em
`${CONFIG_HOST_PATH}/prometheus`, com retenção de 15 dias. Antes da primeira subida,
crie esse diretório com permissão de escrita para `PUID:PGID`. Não há autenticação nem
TLS nesta publicação: use somente na LAN confiável, sem encaminhar a porta no roteador.

Na mesma stack, o `grafana` publica a porta 3001 no `HOST_LAN_IP` (a 3000 é do homepage), com
login `admin` e a senha de `GRAFANA_ADMIN_PASSWORD`, aplicada só na criação do banco. O
datasource do Prometheus vem provisionado de `server/prometheus/grafana/provisioning/`;
dashboards e usuários ficam em `${CONFIG_HOST_PATH}/grafana`, que também precisa existir com
permissão de escrita para `PUID:PGID` antes da primeira subida. Para os gráficos do host,
importe o dashboard 1860 (Node Exporter Full) em Dashboards → New → Import.

Os alertas também são provisionados, de `server/prometheus/grafana/provisioning/alerting/`, e
avisam num canal do Discord pelo webhook de `DISCORD_WEBHOOK_URL`: CPU presa em 800 MHz
(PROCHOT), CPU acima de 90 °C, disco acima de 90%, HD de mídia (`/mnt/midia`) desmontado ou só
leitura, serviço do systemd em `failed`, container
reiniciando em loop e exporter fora do ar. Regras provisionadas não podem ser editadas pela
interface: mude o `rules.yml` e reinicie o Grafana. Nos templates do arquivo, escreva `.Labels` e
`.Values` em vez de `$labels` e `$values`: o Grafana expande `$VAR` do ambiente nesses arquivos, e o
escape `$$` chega literal na mensagem. O banco SQLite roda em modo WAL (`GF_DATABASE_WAL`), para
que a avaliação dos alertas não falhe com "database is locked" quando o disco está ocupado.

As métricas por container (CPU, memória, rede e I/O) vêm do `cadvisor`, também nessa stack,
sem porta publicada. Ele varre os containers a cada 30s e não mede o espaço em disco de cada
um (o `du` por camada é caro), para poupar a CPU. Precisa dos sockets do Docker e do containerd:
sem o do containerd, as versões novas não enxergam nenhum container.

Os logs dos containers vão para o `loki`, também nessa stack e sem porta publicada. Quem coleta é o
`alloy`, que lê o log de cada container pelo socket do Docker (`server/prometheus/config.alloy`) e o envia
ao Loki com os rótulos `container`, `service_name`, `compose_project` e `stream`. O Loki guarda 15 dias em
`${CONFIG_HOST_PATH}/loki` (configuração em `server/prometheus/loki.yml`), e o Alloy guarda até onde já leu
em `${CONFIG_HOST_PATH}/alloy`. Os dois diretórios precisam existir antes da primeira subida, o do Loki com
permissão de escrita para `PUID:PGID`. O datasource `Loki` vem provisionado no Grafana: consulte em
Explore ou em Drilldown → Logs, por exemplo `{container="jellyfin"} |= "error"`. O Dozzle continua
sendo o caminho rápido para acompanhar um log ao vivo. A imagem do Loki é distroless (sem shell nem wget),
então ele não tem healthcheck. O Alloy não tem wget nem curl, e o healthcheck dele usa o `bash`.

As imagens PNG de painéis (Share → Link → Render image) vêm do `grafana-renderer`, um Chromium
headless na mesma stack, sem porta publicada. Ele abre o painel pelo `http://grafana:3000/` e devolve
o print. Os dois se autenticam com `GRAFANA_RENDERER_TOKEN`: com o token padrão, o Grafana se recusa
a iniciar. Não instale o plugin `grafana-image-renderer` com o `grafana cli`, porque a imagem do
Grafana não tem o Chromium que ele precisa.

Todas as stacks entram na mesma rede Docker (`NETWORK_NAME`), declarada como `external`. A rede é criada pelo `scripts/setup-env.sh`.

Se a sidecar reinicia depois do app (boot lento, por exemplo), o app fica preso num network namespace órfão, só com `lo`, e para de responder pela LAN e pelo tailnet. Por isso o healthcheck de cada app começa com `test -e /sys/class/net/eth0`, e o label `autoheal=true` deixa o `autoheal` (stack `shared`) reiniciar o app, que volta já no namespace atual da sidecar. A imagem do dozzle é `scratch` (sem shell), então o healthcheck dela é só `/dozzle healthcheck` e não detecta o namespace órfão; se o dozzle sumir da rede depois de um reinício da sidecar, reinicie-o à mão. (Montar o busybox via volume `type: image` resolveria; não foi feito porque o CasaOS, já removido, não validava esse compose.)

## Uso

```sh
# A partir da raiz do repositório:
./scripts/setup-env.sh      # cria .env, cria a rede e valida todas as stacks
./scripts/up-all.sh         # sobe todas as stacks
./scripts/update-all.sh     # baixa imagens novas e atualiza todas as stacks
./scripts/down-all.sh       # derruba todas as stacks

# Para operar apenas uma stack:
cd media/sonarr
docker compose up -d
```

O crontab do usuário `davi` executa `scripts/update-all.sh` diariamente às 05:00,
com trava contra execuções simultâneas e log em `docker/.state/docker-update.log`.
O arquivo `system/cron.d/docker-update` permite instalar a mesma rotina pelo cron do
sistema, como alternativa ao crontab do usuário (use apenas um dos dois).
Para essa instalação alternativa, a partir da raiz do repositório:

```sh
mkdir -p docker/.state
sudo install -m 644 -o root -g root system/cron.d/docker-update /etc/cron.d/docker-update
```

O `up-all.sh` também compara a imagem de cada container com a imagem local da mesma tag:
após um pull, recria stacks com imagens novas mesmo se estiverem saudáveis e sem alterações
no compose. O download ignora imagens de build local.
Se o download de uma stack falhar, as demais continuam e as imagens disponíveis são aplicadas;
o script retorna erro ao final para registrar a falha.

## Serviços e portas

| Stack | Porta no host | Porta da aplicação |
| --- | --- | --- |
| sonarr | 8989 | 8989 |
| radarr | 7878 | 7878 |
| prowlarr | 9696 | 9696 |
| lidarr | 8686 | 8686 |
| bazarr | 6767 | 6767 |
| profilarr | 6868 | 6868 |
| qbittorrent | 8080 (sem Tailscale, atrás da Surfshark) | 8080 |
| jellyfin | 8096 | 8096 |
| jellyseerr | 5055 | 5055 |
| bookshelf (fork do Readarr) | 8787 | 8787 |
| calibre | 8082 (GUI), 8081 (content server), 9090 (dispositivo sem fio) | 8080, 8081, 9090 |
| shelfarr | 5056 | 80 |
| lazylibrarian | 5299 | 5299 |
| kosync (KOReader Sync Server oficial) | 17200 (HTTP, só no `HOST_LAN_IP`) | 17200 (HTTP), 7200 (HTTPS autoassinado) |
| questarr | 5000 | 5000 |
| nextcloud (Postgres e Redis em 127.0.0.1, no namespace da sidecar) | 7580 | 80 |
| nextcloud → onlyoffice (editor de documentos, mesma stack) | — (tailnet e rede Docker) | 80 |
| homepage (dashboard dos apps) | 80 e 3000 | 3000 |
| dozzle (logs dos containers) | 8888 | 8080 |
| falaai (podcast das newsletters, imagem de build local) | — (só tailnet: `https://falaai.<tailnet>.ts.net`) | 8000 |
| prometheus (métricas, sem Tailscale) | 9091 (HTTP, só no `HOST_LAN_IP`) | 9090 |
| node-exporter (métricas do host, rede do host) | 9100 (HTTP, só no `HOST_LAN_IP`) | 9100 |
| grafana (gráficos do Prometheus, mesma stack) | 3001 (HTTP, só no `HOST_LAN_IP`) | 3000 |
| cadvisor (métricas por container, mesma stack) | — (só rede Docker) | 8080 |
| loki (logs dos containers, mesma stack) | — (só rede Docker) | 3100 |
| alloy (coletor de logs para o Loki, mesma stack) | — | 12345 (só no container) |
| grafana-renderer (PNG de painéis, mesma stack) | — (só rede Docker) | 8081 |
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
   docker compose -f server/backup/docker-compose.yml up -d
   docker exec backup backup
   ```

### Restaurar

```sh
gpg -d media-stack-<data>.tar.zst.gpg | zstd -d | tar -x
# backup/media-stack/<serviço>/ -> ${CONFIG_HOST_PATH}/<serviço>/   (com o container parado)
# backup/env/.env               -> docker/.env
```

## KOSync (progresso do KOReader)

Para usar diretamente na LAN, configure o servidor personalizado do KOReader como
`http://<HOST_LAN_IP>:17200` (por exemplo, `http://192.168.100.35:17200`). A porta é publicada
somente no IP definido por `HOST_LAN_IP`; a variável é obrigatória para evitar um bind acidental em
todas as interfaces. O Kindle precisa estar na mesma rede e conseguir acessar esse IP. HTTP não
cifra o tráfego: use apenas em rede confiável e não encaminhe essa porta no roteador.
O acesso HTTPS pelo Tailscale continua disponível em `https://kosync.<tailnet>.ts.net`.

Para cadastrar uma conta pelo KOReader, altere temporariamente `ENABLE_USER_REGISTRATION=false`
para `ENABLE_USER_REGISTRATION=true` no `docker-compose.yml` desta stack e recrie a aplicação:

```sh
cd ~/my-servers-config/docker/books/kosync
docker compose up -d --force-recreate kosync
```

Com um livro aberto, use **Sincronização de progresso → Registrar/Entrar** no KOReader.
Depois de criar as contas necessárias, volte a variável para `false` e repita o comando;
isso fecha novos cadastros sem apagar as contas existentes. Um simples `docker compose restart`
não aplica alterações de variáveis de ambiente.

Por padrão, o registro fica desligado (`ENABLE_USER_REGISTRATION=false`). Como alternativa ao cadastro
pelo KOReader, crie a conta direto no Redis, no **db 1** (o db do ambiente `production`). A chave é o MD5
da senha, o mesmo valor que o KOReader envia:

```sh
key=$(printf %s '<senha>' | md5sum | cut -d' ' -f1)
docker exec kosync redis-cli -n 1 SETNX user:<usuario>:key "$key"
```

### Calibre (plugin KOReader Sync)

O plugin [KOReader Sync](https://github.com/kyxap/koreader-calibre-plugin) (v0.8.2) lê o progresso de dois jeitos:

- **ProgressSync:** todo dia às 04:00, com a GUI aberta (o container mantém), ou pelo menu do plugin. Ele consulta
  `http://kosync_tailscale:17200/syncs/progress/<#ko_md5>` como `davi` e preenche progresso, local, dispositivo e
  datas. Só pega livros com `#ko_md5` preenchido e status vazio ou `reading`.
- **Dispositivo sem fio:** com o KOReader conectado pela porta 9090, lê os sidecars `.sdr` e preenche também
  status, nota, resenha, marcações e o próprio `#ko_md5`.

O `#ko_md5` é o `document` que o dispositivo manda ao kosync, e cada um calcula de um jeito:

- **CrossPoint** (modo *Filename*): `md5` do nome do arquivo no dispositivo. O driver CrossPoint Reader envia como
  `{title} - {authors}.epub` (via `ascii_filename`), então o Calibre consegue calcular. O `fill-ko-md5.py` preenche
  os livros com a coluna vazia, usando o próprio driver para gerar o nome. Rode depois de adicionar livros:

  ```sh
  docker stop calibre
  docker run --rm --user 1000:1000 -e HOME=/config -v ${CONFIG_HOST_PATH}/calibre/config:/config \
    -v "$PWD/books/calibre":/work:ro --entrypoint calibre-debug lscr.io/linuxserver/calibre:latest /work/fill-ko-md5.py
  docker start calibre
  ```
  (Com a GUI parada: ela mantém um cache e não veria a mudança.)
- **Kindle** (KOReader, modo *binary*): *partial MD5* do conteúdo do arquivo no Kindle. Ele difere do arquivo da
  biblioteca, porque o Calibre reescreve os metadados ao enviar. Esse hash chega pela sincronização sem fio do plugin.
  Essa sincronização **sobrescreve** o
  `#ko_md5` com o hash do Kindle.

A coluna guarda um hash por livro, então o Calibre acompanha um dispositivo por livro. Para unificar, o KOReader do
Kindle teria que usar o modo *Filename*, e o driver sem fio teria que ter o mesmo template do CrossPoint (hoje é
`{title} - {authors} ({id})`).

As 16 colunas `#ko_*` foram criadas com os formatos padrão do plugin. A config fica em
`${CONFIG_HOST_PATH}/calibre/config/.config/calibre/plugins/KOReader Sync.json`.

O zip instalado tem um patch de uma linha, do [PR #159](https://github.com/kyxap/koreader-calibre-plugin/pull/159),
para o [bug #163](https://github.com/kyxap/koreader-calibre-plugin/issues/163). O plugin divide por 1000 o
`timestamp` do kosync, que vem em segundos, e as datas caíam em 1970. Ao atualizar o plugin, confira se o PR já
entrou; se não, reaplique:

```sh
sed -i "s|progress_data\['timestamp'\]/1000|progress_data['timestamp']|" action.py
```

## Nextcloud e OnlyOffice

O OnlyOffice está na stack `nextcloud`, com sidecar própria (`onlyoffice-ts-serve.json`). Instalação limpa em `${CONFIG_HOST_PATH}/nextcloud` e `${CONFIG_HOST_PATH}/onlyoffice` (a do CasaOS ficou em
`/DATA/AppData/big-bear-*`). Com `html/` vazio, a imagem instala sozinha com Postgres em `127.0.0.1` e a conta
`NEXTCLOUD_ADMIN_USER`/`NEXTCLOUD_ADMIN_PASSWORD` do `.env`. Uma pasta `html/` que já tem `version.php` não é
reinstalada, mesmo sem `config.php`: para recomeçar, apague `html/` e `db/` com a stack parada.

O Nextcloud responde em três endereços: `https://nextcloud.<tailnet>.ts.net` (tailscale serve), `http://<HOST_LAN_IP>:7580`
e `http://tailscale-nextcloud` (rede Docker, usado pelo OnlyOffice). Entre os serviços, use o nome do serviço
(`tailscale-nextcloud`, `tailscale-onlyoffice`), não o `container_name`: o `_` não vale em hostname e o cliente HTTP
do Nextcloud o codifica (`onlyoffice%5ftailscale`), quebrando a conversão. `OVERWRITECONDADDR=^127\.0\.0\.1$` faz o https e o
host do tailnet valerem só para o que chega pelo tailscale serve; os outros dois seguem em http. O que a imagem só grava
na instalação (trusted domains, cron, app onlyoffice) é reaplicado a cada start por `hooks/before-starting/10-config.sh`.
O que fica no banco e basta fazer uma vez (instalar o app onlyoffice, criar a pasta Mídia) roda só após a instalação,
por `hooks/post-installation/10-setup.sh`.

O editor abre no navegador em `https://onlyoffice.<tailnet>.ts.net`, então só funciona para quem está no tailnet. Na LAN
os arquivos abrem, mas a edição não. O segredo JWT (`ONLYOFFICE_JWT_SECRET`) é o mesmo nos dois serviços.

O HD de mídia aparece para todos os usuários como a pasta **Mídia** (External Storage local, `${DATA_HOST_PATH}`
montado `:ro` em `/mnt/midia`). É só leitura duas vezes, no bind e na opção `readonly` do mount, porque a biblioteca é
dos *arr: apagar ou mover pelo Nextcloud quebraria hardlinks e seeding. As prévias estão desligadas, para o Nextcloud
não gerar miniaturas da biblioteca inteira. O mount fica no banco do Nextcloud, não no compose. O hook
post-installation o cria; para recriar à mão:

```sh
docker exec -u www-data nextcloud php occ app:enable files_external
docker exec -u www-data nextcloud php occ files_external:create Mídia local null::null -c datadir=/mnt/midia
docker exec -u www-data nextcloud php occ files_external:option <id> readonly true
docker exec -u www-data nextcloud php occ files_external:option <id> previews false
```

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

## Fala Aí

A stack `apps/falaai` constrói a imagem a partir do código em `FALAAI_SRC` (padrão `/home/davi/falaAi`,
clone de github.com/SoaresDavidson/falaAi): o `update` ignora essa imagem, então depois de um `git pull`
lá rode `docker compose up -d --build` aqui. Banco, episódios e o `gmail-token.json` ficam em
`${CONFIG_HOST_PATH}/falaai` (dono 1000:1000) e entram no backup. Ollama e Kokoro rodam no laptop,
pela tailnet; setup do laptop e uso no README do falaAi. O Prometheus coleta em `falaai_tailscale:8000`
pela medianet, e os alertas ficam em `grafana/provisioning/alerting/falaai-alertas.yaml`.
