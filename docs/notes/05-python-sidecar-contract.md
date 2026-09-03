> **Non-normative.** Where this conflicts with
> [spec-01](../spec-01-catalog-data-model.md), the specification governs.
>
> **Superseded here:** nothing structural. The named-not-positional wire contract stands and carries into the ingest specification; `extractor_version` becomes a provenance obligation in the annotation specification.

# 05 — Python Sidecar Contract

## Why it exists

Exactly one capability keeps Python in the stack: **music information retrieval**. A Hex-wide
search confirmed that constant-Q transform, chroma, MFCC/DCT, beat tracking, onset detection, and
chromaprint have **no Elixir implementation and no native binding** — not thin options, nothing.

`nx_signal` provides the transform layer (STFT, mel, windows, FFT). The feature layer above it does
not exist. Building it would be original work: a CQT and an Ellis-style dynamic-programming beat
tracker are each a real project.

Containerized deployment makes a language boundary cheap. This is a deliberate trade, not a failure.

## What the sidecar contains

Only this:

- `analyzer.py` — the `TransformCache` and all librosa transforms
- `_analyze_worker.py::analyze_one_song` — scalar features, segment vectors, contrast profile
- chromaprint fingerprinting (`fpcalc` / `pyacoustid`)
- **optionally** CLAP encoding and AST instrument detection (see below)

Everything else in the current Python app is deleted: `web.py`, the entire `frontend/`, the
pipeline half of `cli.py`, `db.py`, `similarity.py`, `taste.py`, `recommendation.py`, and
`vector_norm.py`.

### Should CLAP stay in Python?

Two options, both defensible:

| Option | Argument |
|---|---|
| **Keep in the sidecar** | Zero work. It already runs there. Simplest first cut. |
| **Move to Ortex** | `nx_signal`'s `stft_to_mel` produces exactly the input CLAP expects. Puts embedding on the inference node with everything else, drops torch from the image, and shares GPU memory with CLIP and Whisper. |

**Recommendation:** export CLAP to ONNX regardless (it decouples from torch and shrinks the image),
but move it to Ortex only after the serving layer is done. If it moves, split the sidecar into a
CPU-only `analyzer` with no torch at all.

## Wire contract: named features, not a positional vector

**This is the most important design decision in this document.**

The current 107-dimension canonical ordering is an invariant spread across five places —
`to_raw_vector()`, `VECTOR_DIM_CONFIG`, `FEATURE_VECTOR_DIM`, `FEATURE_GROUPS`, and
`SEGMENT_VECTOR_MAP` — all within one language, where at minimum a test can catch drift. Splitting
that across a language boundary makes it materially worse.

So the sidecar returns **named** scalars and arrays. Elixir assembles the vector.

```jsonc
{
  "schema_version": 1,
  "extractor_version": "librosa-0.10.1/ma-2026.09.02",
  "duration": 241.3,
  "sample_rate": 22050,
  "scalars": {
    "tempo": 128.4,
    "spectral_centroid_mean": 2841.2,
    "spectral_bandwidth_mean": 1904.7,
    "rms_mean": 0.081,
    "swing": 0.13,
    "syncopation": 0.42
    // … every scalar dimension, by name
  },
  "arrays": {
    "mfcc_mean":        [/* 13 */],
    "mfcc_std":         [/* 13 */],
    "spectral_contrast":[/*  7 */],
    "chroma_mean":      [/* 12 */],
    "chroma_std":       [/* 12 */],
    "freq_bands":       [/*  7 */],
    "dynamic_arc":      [/*  4 */]
  },
  "segments": [
    {
      "index": 0,
      "start": 0.0,
      "end": 14.2,
      "scalars": { /* … */ },
      "arrays":  { /* … */ }
    }
  ],
  "fingerprint": { "chromaprint": "AQAA…", "duration": 241 }
}
```

### What Elixir owns as a result

- Canonical dimension ordering — **one module**, not five files
- Min-max normalization ranges and perceptual weights
- Writing `song_features` columns and the pgvector column
- `rebuild-vectors` equivalent: pure Elixir over DB columns, **no sidecar call**

### Why this is better

| Property | Positional vector | Named features |
|---|---|---|
| Ordering invariant | 5 places, 2 languages | 1 module, 1 language |
| Adding a dimension | coordinated release | additive — sidecar emits a new name, Elixir adds a `DimConfig` |
| Old rows after a change | silently misaligned | detectably missing a key |
| Re-normalization | needs the extractor | pure DB operation |
| Sidecar bug blast radius | can corrupt vector layout | can only produce a bad scalar |

## Versioning

Two independent version fields, both required:

- **`schema_version`** — the wire format. Bump on structural change. Elixir refuses unknown majors.
- **`extractor_version`** — the *numerical* identity of the extraction code: library versions plus
  our own build. Stamped onto every `song_features` and `segment_features` row.

`extractor_version` is what makes the drift problem tractable. Any reimplementation or library
upgrade shifts the numbers, invalidating stored vectors and resetting the taste profile. With this
column, "re-analyze everything extracted before version X" is a query rather than archaeology.

> **Do this first.** Add `extractor_version` to the existing Python schema and backfill it *before*
> any migration work begins. It is a one-line change now and impossible to reconstruct later.

## Orchestration

**Elixir/Oban owns the work loop. The sidecar is a stateless HTTP service.**

```
Oban job (per song)
   │
   ├─ POST /analyze  { "path": "/music/…/track.flac" }
   │      sidecar reads from the shared read-only volume
   │      returns named features (above)
   │
   └─ Elixir writes song_features, segment_features, fingerprints,
      assembles + normalizes vectors, writes pgvector columns
```

### Why not the AudioMuse pattern

AudioMuse uses its `task_status` table as a queue with `LISTEN`/`NOTIFY`, and the Python worker
polls it. That is a good design *for AudioMuse*, which had no job runner. We already have Oban:
retries with backoff, unique jobs, per-queue concurrency, and `oban_web` (open source as of Oban
2.19) for observability.

Keeping the sidecar stateless additionally gives us:

- no database credentials in the Python container
- no schema coupling — **Ecto stays the sole migration owner**
- free restart and redeploy; in-flight jobs simply retry
- an independently versionable contract

## Concurrency — the failure mode to avoid

The current design runs a `ThreadPoolExecutor` with `ANALYSIS_WORKERS=24` *inside* Python. If Oban
also enforces a queue limit, two schedulers compete for the same cores and the result is either an
idle box or an OOM, neither obviously attributable.

**Rules:**

1. The sidecar handles **one song per request, synchronously**. Delete the thread pool.
2. Oban's queue `limit` is the **only** concurrency knob.
3. Size the Python side to match: `uvicorn --workers N` where `N ≥` the Oban limit for `:extract`.
4. Set a generous Oban `timeout` — minutes, not seconds.

## Failure handling

The sidecar returns structured errors and **never touches the database**.

```jsonc
{ "error": { "kind": "decode_failure", "detail": "…", "retryable": false } }
```

Elixir decides what that means:

| `kind` | Oban behaviour | Side effect |
|---|---|---|
| `decode_failure`, `too_short`, `unsupported` | discard | write `CorruptFile` row |
| `timeout`, `resource_exhausted`, 5xx, connection refused | retry with backoff | none |

This preserves the existing `CorruptFile` table and the `/corrupt` UI page.

## Container topology

```yaml
# illustrative, not final
db:        postgres + pgvector          # Ecto owns the schema
web:       phoenix                      # API, LiveView, OpenSubsonic, playback
inference: elixir node                  # Nx.Servings, GPU
analyzer:  python sidecar               # librosa + fpcalc, CPU only, no torch
gpu:       python sidecar (optional)    # CLAP + AST, GPU reservation
```

- Both sidecars mount `music:/music:ro`.
- Neither sidecar has database access.
- `gpu` sits behind a compose profile so it is not always up.
- Splitting `analyzer` from `gpu` is optional but pays twice: the CPU image drops torch entirely and
  becomes small, and the GPU one can move to another machine without touching anything else.

## Testing the boundary

Because the sidecar is stateless and returns named values, it is unusually testable:

1. **Golden fixtures.** A small set of audio files with committed expected output. Catches
   library-upgrade drift immediately.
2. **Parity harness.** During migration, run the current in-process pipeline and the sidecar over
   the same files and diff per dimension. `SegmentFeatures.features_json["vector"]` holds raw
   unnormalized values, so the comparison happens before normalization can mask anything.
3. **Contract tests in Elixir.** Assert that every name in `VECTOR_DIM_CONFIG` appears in the
   sidecar's response for a known file — this is what replaces the old five-file lockstep.
