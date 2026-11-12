# M4: places from GPS and events

**Date:** 2026-11-12  
**Agent:** Claude Code  
**Brief:** section 7 (event detection and smart grouping), 6.2 (no invented places), phase 4.

## Places (`app/places/`)

- Data: GeoNames `cities500` (every place with 500+ inhabitants, 226,153 populated places after dropping city sections and historical places), region and country names. License CC BY 4.0, attribution GeoNames. Downloaded once by `scripts/download-geodata.sh` into `local-data/geo/` (42 MB, not in git); approved by the owner. Lookups are offline; coordinates never leave the Mac.
- Rules: within 2.5 km the largest place wins (precision "in"), else the nearest place within 10 km ("near X"), else only region and country. No GPS means no place. `0,0` coordinates count as missing.
- Other names of the place (GeoNames alternate names, e.g. Firence, Firenze) are stored so search works in Slovenian. Region names have no alternates in GeoNames, so "Toskana" does not match "Tuscany" yet.

## Events (`app/timeline/event_detector.py`)

- Per local day, all sources together, clock corrections applied. A new event starts after a gap of more than 2 h, after more than 30 min with a move of more than 2 km, or after a jump of more than 15 km.
- Names come only from facts: the most common GPS place plus the part of the day of the middle photo ("Florence, afternoon"). Without GPS just the part of the day ("Evening").
- The owner can rename an event, merge it with the previous one, start a new event at a photo, and undo all edits of a day. An edited day is locked: re-analysis keeps its events and adds new photos to the nearest event by time.

## Other changes

- Clock differences of 2 s or less are reported as "clock matches" instead of a correction (the iPhone's GPS time lagged its clock by 0.8 s, which is a GPS fix delay, not a wrong clock).
- Search: a word matching a photo's GPS place (or its other names) adds 0.10 and is marked "place match".

## Verified

- 64 pytest tests (7 new): place rules with a fake index, event splitting and naming, edits that survive re-analysis, undo, no place without GPS, Slovenian place names in search, event API, clock within 2 s.
- `test-10` (now 19 photos: 10 Sony + 9 iPhone 18 Pro Max HEIC with GPS, added by the owner): full analysis 11 s. Places: 7 "in", 2 "near" (Florence, San Gimignano, near Pienza, near Colle di Val d'Elsa). 8 events, e.g. "near Pienza, evening", "Florence, morning". A Florence photo shows the Ponte Vecchio, consistent with the GPS place. iPhone times cross the DST change correctly (+02:00 on 24 Oct, +01:00 from 26 Oct). Search "Firence" returns the Florence photos first. Split, undo and place details checked in the browser.

## Not done

- The iPhone photos are Live Photo stills without their `.MOV` files, so Live Photo pairing on real files is still untested.
- Events are not yet used for export folders (M5) and photos cannot be dragged between events (only split and merge).
- Landmark names (e.g. "Ponte Vecchio") are not used: that needs evidence beyond the nearest town.
