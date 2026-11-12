#!/bin/sh
# Download the GeoNames place list used for offline place names (M4).
#   cities500.zip      every place with 500+ inhabitants (~12 MB zipped)
#   admin1CodesASCII   region names (e.g. Tuscany)
#   countryInfo.txt    country names
# Source: https://download.geonames.org/export/dump/ - license CC BY 4.0
# (attribution: GeoNames, geonames.org). Stored in local-data/geo (not in git).
set -e
cd "$(dirname "$0")/.."
mkdir -p local-data/geo
cd local-data/geo
curl -fsSLO https://download.geonames.org/export/dump/cities500.zip
curl -fsSLO https://download.geonames.org/export/dump/admin1CodesASCII.txt
curl -fsSLO https://download.geonames.org/export/dump/countryInfo.txt
unzip -o -q cities500.zip
rm cities500.zip
ls -la
