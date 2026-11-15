#!/usr/bin/env bash
# Grava os .sql de user-ops/ como user ops (pcd_ops, origin='user') no Profilarr v2.
# A API do v2 não cria custom formats/scores (só a UI), então escrevemos direto na
# camada user, que é recompilada sobre as ops base a cada start e sobrevive aos pulls.
# Idempotente: reaplicar substitui a op de mesmo nome de arquivo.
set -euo pipefail

cd "$(dirname "$0")"
set -a; . ../../.env; set +a

DB="${CONFIG_HOST_PATH}/profilarr/v2/data/profilarr.db"
DB_NAME="${1:-Dictionarry}"

docker compose --env-file ../../.env stop profilarr
cp "$DB" "$DB.bak-$(date +%Y%m%d-%H%M%S)"

python3 -I - "$DB" "$DB_NAME" user-ops/*.sql <<'EOF'
import hashlib, json, os, sqlite3, sys
db_path, db_name, *files = sys.argv[1:]
db = sqlite3.connect(db_path)
row = db.execute("select id from database_instances where name = ?", (db_name,)).fetchone()
if not row:
    sys.exit(f"banco PCD '{db_name}' não encontrado em database_instances")
dbid = row[0]
with db:
    for f in files:
        name = os.path.basename(f)
        sql = open(f, encoding="utf-8").read()
        db.execute("delete from pcd_ops where database_id=? and origin='user' and filename=?", (dbid, name))
        db.execute(
            "insert into pcd_ops (database_id, origin, state, source, filename, sql, metadata, content_hash)"
            " values (?, 'user', 'published', 'local', ?, ?, ?, ?)",
            (dbid, name, sql,
             json.dumps({"operation": "user", "entity": "batch", "name": name}),
             hashlib.sha256(sql.encode()).hexdigest()))
        print("aplicado:", name)
EOF

docker compose --env-file ../../.env start profilarr
echo "Confira: docker logs profilarr | grep 'Cache compiled'  (deve mostrar \"user\":N)"
