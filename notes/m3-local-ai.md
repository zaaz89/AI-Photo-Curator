# M3: local AI (search, descriptions, tags)

**Date:** 2026-11-12  
**Agent:** Claude Code  
**Brief:** section 6 (AI visual understanding), 6.2 (confidence), 15 (privacy), 17 (performance).

## Models (approved by the owner, stored in the project)

| Job | Model | License | Size | Where |
|---|---|---|---|---|
| Search (image and text embeddings) | `google/siglip2-base-patch16-224` | Apache 2.0 | 1.4 GB | `local-data/models/huggingface` |
| Descriptions, tags, query translation | `qwen3-vl:4b` via Ollama 0.40 | Apache 2.0 | 3.3 GB | `local-data/models/ollama` |

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

## Not done or not verified

- No place names yet: GPS reverse geocoding and landmark evidence are needed first (brief 6.2). Planned with events (M4).
- Face analysis (brief 6.1) is not started.
- Quality of all 202 descriptions has not been reviewed; only samples were read.
- Search above 236 photos is untimed. It is a full matrix product, fine for tens of thousands of vectors.
