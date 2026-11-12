# M6: one app, English and Slovenian

**Date:** 2026-11-12  
**Agent:** Claude Code  
**Brief:** section 12 (user interface), phase 6. Owner's choices: English by default with Slovenian as an option; move all upstream features into the new app at once and remove the old page.

## What changed

- `/` is now one page (`app/web/templates/app.html`, `app/web/static/app.js`, `app.css`): sidebar with Library, Timeline, Best photos, Duplicates, Search results, Export, Sources & clocks, Settings; toolbar with search and thumbnail size; inspector panel; Quick Look. System font, system blue accent, light and dark from macOS, one colour per person or device.
- Language: `ui_language` setting (`en` default, `sl`). All UI text and known server warnings are translated in the browser.
- Upstream features moved onto the collection index (`app/quality/scoring.py`):
  - Focus tiers (sharp, soft, blurry) with the upstream region sharpness, adaptive thresholds and "rescue" of well-composed soft shots. The owner can override a tier (keys 1 2 3, 0 back to auto). Marks only.
  - Best photos: the upstream five-category ranking with editable weights (saved in settings), top N, remove/restore, and "Export these" (smart export with `selection=best`).
  - Phone wallpapers: flag photos (key B) and export originals plus 1290×2796 crops through the verified exporter.
  - Smart export gained `selection`: all, all except blurry, best only.
- Analysis now also stores focus and ranking scores per file content (`quality`, about 0.1 s per photo on the CPU, with the same duty-cycle limit as the AI jobs). Marks (`marks`) are stored by content.
- Removed: the upstream HTML page and its folder-based routes (`/api/run`, `/api/export`, `/api/toggle-status`, phone BG routes, SD-card shortcuts), the old `/timeline` page (now redirects to `/`), `photo_dedup_batch.py` and `photo_ranking_engine.py` (replaced by `app/duplicates` and unused). The MapLibre map and its internet tile requests are gone; the CSP now allows nothing from the internet.
- Keyboard: arrows move, Space Quick Look, Esc closes, 1/2/3/0 focus, B wallpaper, X remove from Best; in Duplicates ↑↓ group, ←→ photo, K keep.

## Verified

- 73 pytest tests (6 new in `test_quality_marks.py`: tier rules, blurry left out of Best, marks surviving re-analysis, export selection, settings validation, marks and Best API). The safety test now runs the whole new workflow (analysis, marks, three export selections, wallpaper export) and checks the sources stay byte-identical with no hidden files; the old move endpoints return 404/405; the page and assets load; the CSP has no `https:`.
- In the browser on `test-10`: Library with filters and inspector, arrow keys, Quick Look, focus override by key and back to auto, Timeline by events, Best photos with weights, Duplicates, Export preview, Sources & clocks, Settings; English and Slovenian; dark and light.

## Not done

- No GPS map (the upstream map loaded tiles from the internet; a local map needs offline tiles).
- Drag and drop between events, multi-select and batch marks.
- The ranking is the upstream heuristic; "Overall look" is a formula, not a learned aesthetic model.
