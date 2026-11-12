# AI Photo Curator log

**Purpose:** Full history, decisions and handoffs between Codex (ChatGPT) and Claude Code. Read before working on this project.

Append new entries at the bottom. Update an existing entry in place instead of adding a near-duplicate. Each entry names the agent.

### 2026-11-12 — Repository set up (Claude)
The owner forked `kotyzap/Photo-Curator` v7.0 (commit `1cb56a0`, 101 commits) to `zaaz89/AI-Photo-Curator`. Local copy is in `~/Documents/ChatGPT/AI Photo Curator`; remote `origin` is the fork, `upstream` the original. The fork is public (GitHub does not allow private forks of public repos), so no personal data goes into git.
Added `project-brief.md` (owner's brief, kept as a living document), `AGENTS.md` (shared rules for Codex and Claude), `CLAUDE.md` (imports AGENTS.md), `.gitignore`.
Decision: both Codex and Claude work on this repo through branches and PRs; the owner merges.
Not done: no code was inspected, run or changed. Phase 0 audit has not started.
Next: Phase 0 repository audit (brief section 18 and 22). Agree with the owner which agent does it.

### 2026-11-12 — Phase 0 audit (Claude)
Owner assigned Phase 0 to Claude. Audit is in `notes/phase-0-audit.md` (branch `claude/phase-0-audit`).
Key findings: three code paths move originals (tier toggle, dedup auto-move, move blurry); analysis writes `.dedup_sig_cache.json` into the source folder; dry run creates folders; exports land inside the source folder. Capture time prefers IFD0 `DateTime` over `DateTimeOriginal` (confirmed by probe), no time zones, sort by filename, non-recursive scan. Pillow 11.3.0 has 57 known advisories; fixes need Pillow 12+, which needs Python 3.10+. Runs natively on Apple Silicon with Python 3.9 and 3.12. No tests.
Proposed plan: M0 safety lock (small PR), then M1 multi-source indexing and timeline in a new `app/` package with SQLite and ExifTool.
Not done: no code changed. Duplicate accuracy not measured (no real photos yet).
Next: owner answers the open questions in section 10 of the audit and decides who does M0 and M1.
