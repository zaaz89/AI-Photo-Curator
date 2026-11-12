"""Full pipeline for a collection: index -> capture times -> clocks -> duplicates."""
from __future__ import annotations

from typing import Callable, Optional

from app.duplicates.groups import build_groups, compute_features
from app.importers.local_importer import index_collection
from app.timeline.clock_sync import sync_clocks


def analyze_collection(conn, progress: Optional[Callable] = None,
                       cancelled: Callable[[], bool] = lambda: False) -> dict:
    res = index_collection(conn, progress, cancelled)
    if cancelled():
        return res
    res['clocks'] = sync_clocks(conn, progress, cancelled)
    from app.places.places import assign_places
    from app.timeline.event_detector import detect_events
    res['places'] = assign_places(conn)
    res['events'] = detect_events(conn)
    if progress:
        progress('Visual signatures', 0, 0)
    res['features_computed'] = compute_features(conn, progress, cancelled)
    # Focus, ranking and faces first: the duplicate keeper uses them.
    from app.quality.scoring import compute_quality
    from app.quality.faces import compute_faces, compute_videos
    res['quality'] = compute_quality(conn, progress, cancelled)
    res['faces'] = compute_faces(conn, progress, cancelled)
    res['videos'] = compute_videos(conn, progress, cancelled)
    res['duplicate_groups'] = build_groups(conn, progress, cancelled)
    # Search index (M3). Optional: without the local model the rest still works.
    from app.ai.embeddings import ModelUnavailable, compute_embeddings
    try:
        res['search_index'] = compute_embeddings(conn, progress, cancelled)
    except ModelUnavailable as e:
        res['search_index'] = {'skipped': str(e)}
    return res
