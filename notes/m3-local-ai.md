# M3: local AI (search, descriptions, tags)

**Date:** 2026-11-12  
**Agent:** Claude Code  
**Brief:** section 6 (AI visual understanding), 6.2 (confidence), 15 (privacy), 17 (performance).

## Models (approved by the owner, stored in the project)

| Job | Model | License | Size | Where |
|---|---|---|---|---|
| Search (image and text embeddings) | `google/siglip2-base-patch16-224` | Apache 2.0 | 1.4 GB | `local-data/models/huggingface` |
| Descriptions, tags, query translation | `qwen3-vl:4b-instruct` via Ollama 0.40 | Apache 2.0 | 3.3 GB | `local-data/models/ollama` |

Setup on a new machine: `brew install ollama exiftool`, `uv sync`, `scripts/download-models.sh`. The app starts Ollama itself through `scripts/ollama-serve.sh` (models in the project, loopback only). At runtime the Hugging Face hub runs offline (`HF_HUB_OFFLINE=1`). Photos go only to the Ollama server on 127.0.0.1, as a 768 px JPEG in memory.

Not verified: whether Ollama itself contacts the internet (update checks). The model calls are local; nothing in our code sends data out.

## How it works

- **Search index.** "Index photos" also computes a SigLIP 2 vector per file content (`image_embeddings`, float16), about 0.1 s per photo on Metal. Reruns skip known content.
- **Search.** The query and its English translation (by the local VLM, cached in `query_translations`) are compared with every photo vector; the better score counts. A word found in the photo's AI tags or description adds 0.02, and the result is marked "tag match". The page says that the order is a similarity guess.
- **Descriptions.** The "Describe photos with local AI" button runs a background job: one description, up to 8 tags, people count and visible text per file content, for photos that are not non-keeper duplicates. The prompt forbids naming places, buildings, people or events (brief 6.2). The output is shown as "AI description, not verified (model)". Results are cached per content, model and prompt version (`ai_annotations`). Failed files are retried on the next run.
- If a model is missing, indexing and the timeline still work; search answers with a clear 503 message.

## Measured on the owner's photos (236 JPEGs)

- Search index: 236 photos in about 24 s.
- English queries, judged by looking at the top results: "a man kneeling to propose", "arched courtyard with columns", "church bell tower", "close-up of an engagement ring", "couple kissing" all had correct photos in the top 3.
- Slovenian queries alone were weaker ("moški kleči in zaprosi" missed both kneeling photos). With translation ("man kneeling and asking") both kneeling photos are in the top 3. "zvonik cerkve" → "church bell": top results are the bell tower.
- Descriptions: about 10 s per photo when the Mac is otherwise idle (37 s while tests and the server competed for the GPU). No place or person names appeared in the samples read. Some descriptions repeated the prompt ("no people visible", "text visible is empty"); `tidy_description` removes those sentences when saving and showing them.
- Translation waits for Ollama. While a describe job runs, a search may wait up to 12 s for translation, then searches without it and says so.

## Keeping the Mac cool (owner's request, 2026-11-12)

The owner does not want the MacBook running at full load. macOS cannot cap the GPU share of one process, so long AI jobs (search index, descriptions) use a duty cycle: after each photo or batch that kept the GPU busy for W seconds they rest W × (100 / share − 1) seconds. The share is a setting on `/timeline` (25, 30 default, 50, no limit) stored in `local-data/settings.json`. A running job reads it again after every photo.

Also:
- Ollama runs with macOS background priority (`taskpolicy -b`; checked: priority 4 for `ollama` and `llama-server`), one request at a time, one model loaded.
- The model is unloaded right after a job and after 2 idle minutes (was 10).
- Jobs pause while macOS reports a thermal or performance warning (`pmset -g therm`), and optionally while on battery (off by default). The thermal check has only been tested with simulated output.
- Model answers are capped at 320 tokens. The model sometimes kept listing tags for over 1,000 tokens, which made one description take 20–40 s.

Measured with `ioreg` (GPU "Device Utilization %", whole Mac, sampled every second): idle with the owner's apps 18 % on average; during a describe job at the 30 % setting 30 % on average, with full-load bursts in 39 of 120 samples (a third of the time, as set). One photo takes about 7 s of work plus 16 s of rest.

## Model switch (2026-11-12)

The first model, `qwen3-vl:4b`, is the thinking variant: it writes 300–400 tokens of reasoning even with `think: false`, which three different ways of disabling did not stop. With the 320-token answer cap that left 177 of 202 answers empty, and the code stored them as empty successes. Fixed: empty answers or answers without a description are errors (retried next run), the cap is 1,024 tokens, and a cut-off answer is retried once with a repeat penalty. The owner approved switching to `qwen3-vl:4b-instruct` (no thinking) and removing the old model.

On the `test-10` collection with the 30 % limit: 9 photos described (the tenth is a duplicate and skipped) in 76 s, about 3 s of model work per photo. No empty answers, every photo has tags, people counts were right, no place or person names. Some descriptions interpret the moment ("proposing to a woman"), which matches what is visible.

Valid descriptions from the earlier model are kept; only photos without one are described (owner: do not redo good work).

## Not done or not verified

- No place names yet: GPS reverse geocoding and landmark evidence are needed first (brief 6.2). Planned with events (M4).
- Face analysis (brief 6.1) is not started.
- Quality of all 202 descriptions has not been reviewed; only samples were read.
- Search above 236 photos is untimed. It is a full matrix product, fine for tens of thousands of vectors.
