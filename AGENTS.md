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
- `photo_curator.py` is the upstream Flask app (UI + cull/dedup/rank). New code goes into the `app/` package, not into this file.
- `local-data/` holds app data (caches, databases, recents). Git ignores it.

## Setup, run, test

- Python 3.12 managed by `uv`: `uv sync`. `requirements.txt` is generated from `pyproject.toml` (`uv export`), do not edit it by hand.
- Run the app: `uv run python photo_curator.py` → http://127.0.0.1:5014
- Tests: `uv run pytest`. Every PR runs them and reports the result. `tests/test_source_safety.py` must always pass.
- Dependency audit: `uv run pip-audit -r requirements.txt`.
- ExifTool is required (`brew install exiftool`).
- Real test photos on the owner's Mac: `~/Desktop/photos` (read-only source; never write into it).

## Hard safety rules (from the brief, sections 15 and 16)

- Never delete, move, overwrite or modify original photo or video files, and never alter their EXIF.
- Analysis and dry runs make zero filesystem changes to source folders.
- Exports copy original bytes to a separate destination and are verified with checksums.
- No photos leave the machine without explicit opt-in. No telemetry.
- Local server binds to loopback only.
- Do not commit personal photos, databases, caches, `.env` files or credentials. Test photos live in `local-data/` (ignored by git).
