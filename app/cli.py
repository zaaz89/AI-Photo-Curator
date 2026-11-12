"""Command line access to collections (useful for scripts and agents).

  uv run python -m app.cli create "Tuscany 2026" [--timezone +02:00]
  uv run python -m app.cli add-source <collection> <folder> --owner "Person A"
  uv run python -m app.cli index <collection>
  uv run python -m app.cli timeline <collection> [--limit 50]
  uv run python -m app.cli list
"""
from __future__ import annotations

import argparse
import json
import sys

from app import collections as col
from app.analysis import analyze_collection
from app.timeline.timeline_engine import timeline


def main(argv=None):
    p = argparse.ArgumentParser(prog='app.cli')
    sub = p.add_subparsers(dest='cmd', required=True)
    c = sub.add_parser('create'); c.add_argument('name'); c.add_argument('--timezone')
    a = sub.add_parser('add-source'); a.add_argument('collection'); a.add_argument('folder')
    a.add_argument('--owner', required=True); a.add_argument('--label')
    i = sub.add_parser('index'); i.add_argument('collection')
    t = sub.add_parser('timeline'); t.add_argument('collection'); t.add_argument('--limit', type=int, default=0)
    t.add_argument('--json', action='store_true')
    sub.add_parser('list')
    args = p.parse_args(argv)

    if args.cmd == 'create':
        print(col.create(args.name, args.timezone))
    elif args.cmd == 'list':
        print(json.dumps(col.list_all(), indent=2, ensure_ascii=False))
    elif args.cmd == 'add-source':
        conn = col.open_db(args.collection)
        print(col.add_source(conn, args.folder, args.owner, args.label))
    elif args.cmd == 'index':
        conn = col.open_db(args.collection)
        res = analyze_collection(conn, progress=lambda m, i, n: print(f'  {m} {i}/{n}' if n else f'  {m}',
                                                                     file=sys.stderr))
        print(json.dumps(res, indent=2, ensure_ascii=False))
    elif args.cmd == 'timeline':
        data = timeline(col.open_db(args.collection))
        items = data['items'][:args.limit] if args.limit else data['items']
        if args.json:
            print(json.dumps({'summary': data['summary'], 'items': items}, indent=2, ensure_ascii=False))
            return
        print(json.dumps(data['summary'], ensure_ascii=False))
        for it in items:
            t = it['utc_time'] or it['local_time'] or '?'
            print(f"{t:27} {it['confidence']:8} {it['rule']:22} {it['owner'][:12]:12} "
                  f"{it['device'][:14]:14} {it['rel_path']}")


if __name__ == '__main__':
    main()
