"""Build the on-device place tiles for Normal Reviews.

Usage:
  python3 -I tools/build_tiles.py OUT_DIR --area NAME --box S,W,N,E --food FILE [--food FILE ...] --other FILE [--other FILE ...]

Inputs (any mix):
  *.tsv / *.tsv.gz with columns lat, lon, name, basic, detail, city   (food, from the Overture notebook)
  *.tsv / *.tsv.gz with columns lat, lon, basic                        (other places)
  restaurants.json (v2, the older Bay Area list incl. OpenStreetMap)   (food)
  places-other.bin (NRO1, the older Bay Area list)                     (other)

Output:
  OUT_DIR/manifest.json, OUT_DIR/f/<tile>.json, OUT_DIR/o/<tile>.bin
  Tiles are 0.25° squares named "<floor(lat*4)>_<floor(lng*4)>".
"""
import csv, gzip, io, json, math, os, re, struct, sys
from collections import Counter, defaultdict

TILE = 0.25
KINDS = ['meal', 'quick', 'fast', 'bar']
KIND_RES = [('quick', re.compile(r"coffee|cafe|café|(^|\s|_)tea|juice|smoothie|boba|bubble|bakery|donut|doughnut|bagel|dessert|ice.cream|gelato|frozen|pastry|patisserie|creperie|acai|chocolate", re.I)),
            ('fast', re.compile(r"fast.food|food.truck|food.stand|food.court|sandwich|(^|\s|_)deli|hot.dog|snack", re.I)),
            ('bar', re.compile(r"\bbar\b|(^|_)bar(_|$)|(^|_|\s)pub|brew|wine|winery|beer|taproom|tavern|lounge|cocktail|saloon", re.I))]
LABELS = {'restaurant': 'Restaurant', 'casual_eatery': 'Casual eatery', 'bar': 'Bar', 'coffee_shop': 'Coffee shop', 'winery': 'Winery',
          'fast_food_restaurant': 'Fast food', 'cafe': 'Cafe', 'smoothie_juice_bar': 'Juice bar', 'food_truck_stand': 'Food truck',
          'brewery': 'Brewery', 'food_court': 'Food court'}

GENERIC = {'Restaurant', 'Casual eatery', 'Fast food', 'Food', 'Eat and drink'}
def pretty(c): return c.replace('_', ' ').strip().capitalize()
def kind_of(text):
    text = re.sub(r"bar.and.grill|sushi.bar|salad.bar|oyster.bar|raw.bar", "", text, flags=re.I)
    for k, rx in KIND_RES:
        if rx.search(text): return KINDS.index(k)
    return 0
def tile_of(lat, lng): return f"{math.floor(lat / TILE)}_{math.floor(lng / TILE)}"
def opener(path): return gzip.open(path, 'rt', encoding='utf-8') if path.endswith('.gz') else open(path, encoding='utf-8')
def norm(s): return re.sub(r'[^a-z0-9]', '', s.lower())

def read_food(path):
    if path.endswith('.json'):
        d = json.load(open(path, encoding='utf-8'))
        for a in d['p']:
            lab = d['t'][a[3]]
            yield (a[0] / 1e5, a[1] / 1e5, a[2], lab, a[4] or '', kind_of(lab))
        return
    with opener(path) as f:
        for r in csv.DictReader(f, delimiter='\t'):
            try: la, lo = float(r['lat']), float(r['lon'])
            except (ValueError, KeyError): continue
            name = (r.get('name') or '').strip()
            if not name: continue
            basic, detail = r.get('basic') or '', r.get('detail') or ''
            lab = pretty(detail) if detail and detail != basic else LABELS.get(basic, pretty(basic or 'restaurant'))
            yield (la, lo, name, lab, r.get('city') or '', kind_of(detail + ' ' + basic))

def read_other(path):
    if path.endswith('.bin'):
        b = open(path, 'rb').read()
        assert b[:4] == b'NRO1'
        n = struct.unpack('<I', b[4:8])[0]
        lat = struct.unpack(f'<{n}i', b[8:8 + 4 * n]); lon = struct.unpack(f'<{n}i', b[8 + 4 * n:8 + 8 * n])
        cat = struct.unpack(f'<{n}H', b[8 + 8 * n:8 + 10 * n])
        cats = json.load(open(os.path.join(os.path.dirname(path), 'restaurants.json'), encoding='utf-8')).get('ot', [])
        for i in range(n): yield (lat[i] / 1e5, lon[i] / 1e5, cats[cat[i]] if cat[i] < len(cats) else 'Other place')
        return
    with opener(path) as f:
        for r in csv.DictReader(f, delimiter='\t'):
            try: yield (float(r['lat']), float(r['lon']), pretty(r.get('basic') or r.get('category') or 'other'))
            except (ValueError, KeyError): continue

def main():
    out = sys.argv[1]; args = sys.argv[2:]; food_files, other_files, boxes, area = [], [], [], ''
    while args:
        flag, val = args[0], args[1]; args = args[2:]
        if flag == '--box': boxes.append([float(x) for x in val.split(',')])
        elif flag == '--area': area = val
        else: (food_files if flag == '--food' else other_files).append(val)
    food = defaultdict(list); near = defaultdict(list)
    def similar(a, b):
        if not a or not b: return False
        return a == b or a.startswith(b[:6]) or b.startswith(a[:6])
    for path in food_files:          # first file wins; later files only add places not already there
        added = dup = 0
        for la, lo, name, lab, city, kind in read_food(path):
            nm = norm(name); ci, cj = math.floor(la / 0.0004), math.floor(lo / 0.0005)
            kx = math.cos(math.radians(la)) * 111320; ref = None
            for a in (-1, 0, 1):
                for b in (-1, 0, 1):
                    for r in near.get((ci + a, cj + b), ()):
                        if similar(nm, r[6]) and math.hypot((r[0] - la) * 110540, (r[1] - lo) * kx) <= 40: ref = r; break
                    if ref: break
                if ref: break
            if ref:
                if ref[3] in GENERIC and lab not in GENERIC: ref[3] = lab; ref[5] = kind   # keep the more specific label
                dup += 1; continue
            rec = [la, lo, name[:120], lab, city[:40], kind, nm]
            near[(ci, cj)].append(rec); food[tile_of(la, lo)].append(rec); added += 1
        print(f'food {path}: +{added} (dup {dup})')
    other_rows = [r for path in other_files for r in read_other(path)]
    freq = Counter(c for _, _, c in other_rows)
    ocat_list = [c for c, _ in freq.most_common(254)]
    if len(freq) > 254: ocat_list.append('Other place')
    ocats = {c: i for i, c in enumerate(ocat_list)}; spare = len(ocat_list) - 1
    other = defaultdict(list)
    for la, lo, c in other_rows: other[tile_of(la, lo)].append((la, lo, ocats.get(c, spare)))
    print(f'other: {len(other_rows)} in {len(freq)} categories')
    os.makedirs(os.path.join(out, 'f'), exist_ok=True); os.makedirs(os.path.join(out, 'o'), exist_ok=True)
    tiles = {}
    for tid, recs in food.items():
        labs, li, pts = [], {}, []
        for la, lo, name, lab, city, kind, _ in recs:
            if lab not in li: li[lab] = len(labs); labs.append(lab)
            pts.append([round(la * 1e5), round(lo * 1e5), name, li[lab], city, kind])
        json.dump({'t': labs, 'p': pts}, open(os.path.join(out, 'f', tid + '.json'), 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
        tiles.setdefault(tid, [0, 0])[0] = len(pts)
    for tid, recs in other.items():
        i, j = map(int, tid.split('_')); lat0, lng0 = i * TILE, j * TILE
        xs = [min(65535, max(0, round((lo - lng0) / TILE * 65535))) for la, lo, c in recs]
        ys = [min(65535, max(0, round((la - lat0) / TILE * 65535))) for la, lo, c in recs]
        cs = [c for la, lo, c in recs]; n = len(recs)
        with open(os.path.join(out, 'o', tid + '.bin'), 'wb') as f:
            f.write(struct.pack('<I', n)); f.write(struct.pack(f'<{n}H', *xs)); f.write(struct.pack(f'<{n}H', *ys)); f.write(bytes(cs))
        tiles.setdefault(tid, [0, 0])[1] = n
    man = {'v': 1, 'tile': TILE, 'area': area, 'boxes': boxes, 'kinds': KINDS, 'oc': ocat_list, 'tiles': tiles,
           'src': 'Overture Maps Foundation; © OpenStreetMap contributors'}
    json.dump(man, open(os.path.join(out, 'manifest.json'), 'w', encoding='utf-8'), separators=(',', ':'))
    print(f'tiles: {len(tiles)}  food: {sum(v[0] for v in tiles.values())}  other: {sum(v[1] for v in tiles.values())}')

if __name__ == '__main__':
    main()
