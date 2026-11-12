# AGENTS.md

Shared instructions for every AI agent working on this repository. Two agents work here: OpenAI Codex (ChatGPT) and Claude Code. Claude reads this file through `CLAUDE.md`. Keep all agent instructions in this one file so the two agents never follow different rules.

## Read first, every session

1. `project-brief.md`: scope, requirements and roadmap. It is the source of truth.
2. `project-log.md`: what the other agent did last, decisions and open items.
3. `git fetch origin && git log --oneline -15 origin/main` and the list of open pull requests.

## Collaboration rules

- Never commit directly to `main`. Work on a branch named `codex/<topic>` or `claude/<topic>` and open a pull request. The owner (Žaž) merges.
- Pull `origin/main` before starting. If the other agent has an open PR touching the same files, stop and ask the owner instead of editing in parallel.
- One task per branch. Keep PRs small enough to review.
- Do not rewrite, revert or reformat the other agent's work without a stated reason in the PR description.
- At the end of every work session append an entry to `project-log.md` (newest at the bottom): date, agent, what changed, why, what is open. Update an existing entry instead of duplicating it.
- If a decision changes scope or requirements, update `project-brief.md` in the same PR and note it in the log.
- Report honestly: tests run, results, what was not verified.

## Repository layout

- Remote `origin`: the owner's fork `zaaz89/AI-Photo-Curator`. It is public, so nothing personal goes into git.
- Remote `upstream`: the original open-source project `kotyzap/Photo-Curator` (MIT). Keep its LICENSE and copyright notice. Pull upstream changes only deliberately, through a PR.
- `docs/` is the upstream landing page, not documentation for this fork. Put new architecture notes in `notes/`.
- `photo_curator.py` is the slim server: request guard, security headers, read-only thumbnail/image/EXIF endpoints. The UI is `app/web/templates/app.html` + `app/web/static/` (since M6); everything else lives in the `app/` package.
- `local-data/` holds app data (caches, databases, recents). Git ignores it.

## Setup, run, test

- Python 3.12 managed by `uv`: `uv sync`. `requirements.txt` is generated from `pyproject.toml` (`uv export`), do not edit it by hand.
- Run the app: `uv run python photo_curator.py` → http://127.0.0.1:5014
- Collections from the command line: `uv run python -m app.cli --help` (create, add-source, index, timeline, list).
- Tests: `uv run pytest`. Every PR runs them and reports the result. `tests/test_source_safety.py` must always pass.
- Dependency audit: `uv run pip-audit -r requirements.txt`.
- ExifTool is required (`brew install exiftool`).
- Places (M4): `scripts/download-geodata.sh` once (GeoNames, CC BY 4.0, into `local-data/geo/`).
- Local AI (M3): `brew install ollama`, then `scripts/download-models.sh` once. Models live in `local-data/models/`. The app starts Ollama via `scripts/ollama-serve.sh`. Tests use fake models and never need them.
- Faces and videos (M7): `scripts/build-helper.sh` once (Swift + Apple Vision/AVFoundation, into `local-data/bin/pc-helper`). Without it the app skips face and video analysis; tests never need it.
- Mac app (M8, native SwiftUI in `mac/`, macOS 27): `scripts/build-mac-app.sh` builds `dist/Photo Curator.app` (`--install` copies it to `~/Applications`). It starts the engine from this folder and stops it on quit; rebuild if the folder moves. Swift tests: `scripts/test-mac.sh`. Both scripts use the Xcode 27 toolchain through `DEVELOPER_DIR`; do not change `xcode-select`.
- Native app rules: the engine API is the contract between `mac/` and the Python code; the Swift side only reads photo files (thumbnails, Quick Look). Liquid Glass only on navigation and floating controls, never on photos or inside the sidebar/inspector (no glass on glass). Every string lives in `mac/Sources/CuratorCore/Strings.swift` in English and Slovenian (a test checks it). The web page is frozen: no new features there.
- Real test photos on the owner's Mac: `~/Desktop/photos` (236 photos, read-only source; never write into it).
- Owner's rule (2026-11-12): check changes on real photos with the small collection `test-10` (10 copies in `test-photos/`, ignored by git: 8 Sony A7 IV incl. one near-duplicate pair, 2 Sony A7 III). Full pipeline takes about 10 s. Run the full 236-photo folder or any long AI job only when the owner asks, and never leave a long AI job running without telling the owner.

## Hard safety rules (from the brief, sections 15 and 16)

- Never delete, move, overwrite or modify original photo or video files, and never alter their EXIF.
- Analysis and dry runs make zero filesystem changes to source folders.
- Exports copy original bytes to a separate destination and are verified with checksums.
- No photos leave the machine without explicit opt-in. No telemetry.
- Local server binds to loopback only.
- Do not commit personal photos, databases, caches, `.env` files or credentials. Test photos live in `local-data/` (ignored by git).
