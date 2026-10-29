"""Turn the US Census ZCTA gazetteer into ZIP code centers for the covered states' box.
Usage: python3 build.py 2023_Gaz_zcta_national.txt site/places/zips.json"""
import csv, json, sys
src, out = sys.argv[1], sys.argv[2]
z = {}
with open(src, encoding='utf-8', errors='replace') as f:
    r = csv.reader(f, delimiter='\t')
    head = [h.strip() for h in next(r)]
    gi, la, lo = head.index('GEOID'), head.index('INTPTLAT'), head.index('INTPTLONG')
    for row in r:
        try: lat, lng = float(row[la]), float(row[lo])
        except (ValueError, IndexError): continue
        if 32.4 <= lat <= 49.1 and -124.9 <= lng <= -114.0:
            z[row[gi].strip()] = [round(lat, 4), round(lng, 4)]
json.dump({'src': 'US Census Bureau, 2023 ZCTA Gazetteer (public domain)', 'z': z}, open(out, 'w'), separators=(',', ':'))
print(len(z), 'ZIP codes')
