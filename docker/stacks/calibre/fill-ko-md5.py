# Preenche #ko_md5 (plugin KOReader Sync) com o hash "Filename" do CrossPoint: md5 do nome com que
# o driver CrossPoint Reader envia o EPUB. Só toca livros com a coluna vazia. Rodar com a GUI parada
# (ver stacks/README.md, secao Calibre).
import hashlib
from calibre.library import db
from calibre.customize.ui import device_plugins
drv = next(p for p in device_plugins() if 'crosspoint' in p.name.lower())
cache = db('/config/Calibre Library').new_api
changes, samples = {}, []
for bid in cache.all_book_ids():
    if cache.field_for('#ko_md5', bid):
        continue
    fmts = [f.lower() for f in (cache.formats(bid) or ())]
    if 'epub' not in fmts:
        continue
    _, name = drv._format_upload_path(cache.get_metadata(bid), 'x.epub')
    changes[bid] = hashlib.md5(name.encode()).hexdigest()
    if bid in (39,) or len(samples) < 3:
        samples.append((bid, name, changes[bid][:6]))
check = drv._format_upload_path(cache.get_metadata(39), 'x.epub')[1]
print('check 39:', check, hashlib.md5(check.encode()).hexdigest()[:6])
cache.set_field('#ko_md5', changes)
print('preenchidos:', len(changes))
for s in samples: print(*s)
