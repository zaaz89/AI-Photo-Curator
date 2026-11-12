"""Offline reverse geocoding: GPS coordinates -> nearest named place.

Data: GeoNames cities500 (every place with 500+ inhabitants), admin1 codes
and country names, CC BY 4.0, downloaded once by scripts/download-geodata.sh
into local-data/geo. No coordinates ever leave the machine.

Rules (brief 6.2: never a falsely specific place):
  - Within 2.5 km, the largest place wins (a photo in a city centre is "in
    Florence", not in a tiny hamlet that happens to be closer): precision "in".
  - Otherwise the nearest place within 10 km: precision "near".
  - Otherwise only the region and country: precision "region".
  - No GPS: no place at all.
"""
from __future__ import annotations

import math
import threading
from pathlib import Path
from typing import Optional

import numpy as np

from app.collections import data_dir

IN_KM = 2.5
NEAR_KM = 10.0
SKIP_CODES = {'PPLX', 'PPLH', 'PPLQ', 'PPLW', 'PPLCH'}   # city sections, historical, abandoned, destroyed
_lock = threading.Lock()
_index = None


class GeoUnavailable(RuntimeError):
    pass


def geo_dir() -> Path:
    return data_dir() / 'geo'


class Index:
    def __init__(self, names, lat, lon, pop, cc, admin1, regions, countries, aliases=None):
        self.names, self.lat, self.lon, self.pop = names, lat, lon, pop
        self.aliases = aliases or [''] * len(names)
        self.cc, self.admin1, self.regions, self.countries = cc, admin1, regions, countries

    @classmethod
    def from_rows(cls, rows, regions=None, countries=None):
        """rows: (name, lat, lon, population, country_code, admin1_code). Used by tests."""
        names = [r[0] for r in rows]
        return cls(names, np.array([r[1] for r in rows], np.float64), np.array([r[2] for r in rows], np.float64),
                   np.array([r[3] for r in rows], np.int64), [r[4] for r in rows], [r[5] for r in rows],
                   regions or {}, countries or {})

    @classmethod
    def load(cls) -> 'Index':
        d = geo_dir()
        cache = d / 'cities500-v2.npz'
        src = d / 'cities500.txt'
        if not src.exists():
            raise GeoUnavailable('place data is not downloaded; run scripts/download-geodata.sh')
        regions, countries = {}, {}
        for line in (d / 'admin1CodesASCII.txt').read_text(encoding='utf-8').splitlines():
            parts = line.split('\t')
            if len(parts) >= 2:
                regions[parts[0]] = parts[1]
        for line in (d / 'countryInfo.txt').read_text(encoding='utf-8').splitlines():
            if line and not line.startswith('#'):
                parts = line.split('\t')
                if len(parts) > 4:
                    countries[parts[0]] = parts[4]
        if cache.exists() and cache.stat().st_mtime >= src.stat().st_mtime:
            z = np.load(cache, allow_pickle=False)
            return cls(list(z['names']), z['lat'], z['lon'], z['pop'], list(z['cc']), list(z['admin1']),
                       regions, countries, list(z['aliases']))
        names, lat, lon, pop, cc, a1, al = [], [], [], [], [], [], []
        with open(src, encoding='utf-8') as f:
            for line in f:
                p = line.rstrip('\n').split('\t')
                if len(p) < 15 or p[6] != 'P' or p[7] in SKIP_CODES:
                    continue
                names.append(p[1]); lat.append(float(p[4])); lon.append(float(p[5]))
                pop.append(int(p[14] or 0)); cc.append(p[8]); a1.append(p[10])
                al.append(','.join(a for a in p[3].split(',') if a and not any(ch.isdigit() for ch in a)
                                   and '://' not in a)[:2000])
        idx = cls(names, np.array(lat), np.array(lon), np.array(pop, np.int64), cc, a1, regions, countries, al)
        np.savez(cache, names=np.array(names), lat=idx.lat, lon=idx.lon, pop=idx.pop,
                 cc=np.array(cc), admin1=np.array(a1), aliases=np.array(al))
        return idx

    def reverse(self, lat: float, lon: float) -> dict:
        box = (np.abs(self.lat - lat) < 0.2) & (np.abs(self.lon - lon) < 0.2 / max(0.2, math.cos(math.radians(lat))))
        ids = np.nonzero(box)[0]
        if len(ids) == 0:
            ids = np.argsort((self.lat - lat) ** 2 + (self.lon - lon) ** 2)[:5]
        dist = _haversine_km(lat, lon, self.lat[ids], self.lon[ids])
        near_i = int(ids[np.argmin(dist)])
        within = ids[dist <= IN_KM]
        if len(within):
            best = int(within[np.argmax(self.pop[within])])
            precision = 'in'
        else:
            best, precision = near_i, ('near' if float(dist.min()) <= NEAR_KM else 'region')
        bd = float(_haversine_km(lat, lon, self.lat[best:best + 1], self.lon[best:best + 1])[0])
        cc, a1 = self.cc[best], self.admin1[best]
        region = self.regions.get(f'{cc}.{a1}')
        country = self.countries.get(cc, cc)
        if precision == 'region':
            label = ', '.join(x for x in (region, country) if x)
            name = None
        else:
            name = self.names[best]
            label = name if precision == 'in' else f'near {name}'
        return {'name': name, 'label': label, 'precision': precision, 'distance_km': round(bd, 2),
                'region': region, 'country': country, 'country_code': cc,
                'aliases': self.aliases[best] if name else ''}


def _haversine_km(lat, lon, lats, lons):
    r1, r2 = np.radians(lat), np.radians(lats)
    dlat, dlon = r2 - r1, np.radians(lons - lon)
    a = np.sin(dlat / 2) ** 2 + np.cos(r1) * np.cos(r2) * np.sin(dlon / 2) ** 2
    return 6371.0 * 2 * np.arcsin(np.sqrt(a))


def get_index() -> Index:
    global _index
    with _lock:
        if _index is None:
            _index = Index.load()
        return _index


def set_index(idx) -> None:
    """Testing hook."""
    global _index
    _index = idx
