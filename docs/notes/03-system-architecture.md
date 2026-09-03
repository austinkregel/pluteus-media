> **Non-normative.** Where this conflicts with
> [spec-01](../spec-01-catalog-data-model.md), the specification governs.
>
> **Superseded here:** the three-app topology and the shared `core` library extraction — the project is one Phoenix app with one schema owner. The Oban queue-sizing discipline and the `Nx.Serving` federation argument still stand.

# 03 — System Architecture

## Runtime decision

**Elixir/Phoenix for everything except audio feature extraction.**

The shape of a media server matches OTP unusually well: many long-lived connections, per-player
state machines, background scanning, and a process that must never fully die. A `GenServer` per
playback session under a supervision tree is the obvious model, not a clever trick — and a crashed
transcode does not take the server down.

Specific justifications:

- **Phoenix PubSub** is the answer to cross-device playback state — the genuinely hard part of the
  playback problem, and the thing that would otherwise be hand-rolled badly.
- **LiveView collapses three moving parts into one.** The current music app runs FastAPI, a Vue 3
  SPA with Pinia stores, and a Vite dev proxy — to serve one user. Roughly half that machinery
  exists only because the frontend is a separate application.
- **Membrane** covers media plumbing natively (see [06-media-pipeline.md](06-media-pipeline.md)).
- **pgvector-elixir** supports Ecto and Postgrex with l2 / cosine / inner-product / l1 / hamming /
  jaccard distances and both HNSW and IVFFlat index creation. The storage layer transfers unchanged.
- **Low ecosystem churn.** On a decade horizon this outweighs raw throughput.
- `document-sorter` is already on this stack, with the ingestion pipeline already written.

### Alternatives considered

| Option | Verdict |
|---|---|
| **Rust** | Best runtime; `nghe` proves an OpenSubsonic server works well (in-memory transcoding via the ffmpeg C API, no ffmpeg binary needed). But most of this code is CRUD and I/O where Rust's cost-per-experiment buys nothing. Right for one component, wrong for the app. |
| **PHP / Laravel** | Not a joke option — Ampache has run this exact application since April 2001 and still ships. Excellent at the CRUD 80%. Weakest exactly where a media server is hardest: long-lived connections and shared playback state, where you'd add Swoole/FrankenPHP/Reverb to get what BEAM gives natively. |
| **Node** | Fastest to write, worst aging characteristics. Dependency churn is the specific risk on a ten-year horizon. |

---

## Service topology

```
                         ┌──────────────────────────────┐
                         │  db — Postgres + pgvector    │
                         │  Ecto owns the schema.       │
                         │  Single migration owner.     │
                         └──────────────┬───────────────┘
                                        │
        ┌───────────────────┬───────────┴────────┬───────────────────┐
        │                   │                    │                   │
  ┌─────┴──────┐     ┌──────┴──────┐      ┌──────┴──────┐    ┌───────┴───────┐
  │  music     │     │  documents  │      │   video     │    │  inference    │
  │  Phoenix   │     │  Phoenix    │      │  Phoenix    │    │  Elixir node  │
  │  :4001     │     │  :4000      │      │  :4002      │    │  holds GPU    │
  └─────┬──────┘     └─────────────┘      └──────┬──────┘    │  Nx.Servings  │
        │                                        │           └───────┬───────┘
        │            ── libcluster / Erlang distribution ────────────┘
        │                                        │
  ┌─────┴────────────┐                    ┌──────┴──────────┐
  │ analyzer         │                    │  ffmpeg workers │
  │ Python sidecar   │                    │  (OS processes, │
  │ librosa + fpcalc │                    │   supervised)   │
  │ CPU only         │                    └─────────────────┘
  └──────────────────┘

  Volumes:  music:/music:ro   video:/video:ro   model-cache:/cache
```

### Why separate apps rather than an umbrella

- `document-sorter` already exists standalone and works. Don't restructure what works.
- Video transcoding has different failure modes and resource appetite; restart it without
  interrupting music playback.
- `Nx.Serving` federation (below) means "shared inference" costs nothing architecturally, which
  removes the main argument for an umbrella.
- Separate repos let a stable app stay untouched while another churns.

A shared `core` library (path dependency or private Hex package) holds: the Oban ingestion pipeline
pattern, pgvector helpers and index migrations, the file watcher, and `Nx.Serving` client wrappers.

---

## GPU sharing — the decisive detail

> All `Nx.Serving`s are distributed by default. If the current machine does not have an instance
> running, `batched_run/3` automatically looks for one in the cluster. Nodes do not need to run the
> same code or applications — only the same Nx version. Load balancing accounts for partition
> counts, so a node with 4 GPUs receives double the requests of a node with 2.

This means **one inference node** holds CLAP, CLIP, the text embedder, and Whisper, and all three
apps call `Nx.Serving.batched_run(Embeddings, input)` with:

- no HTTP layer
- no serialization code
- no duplicated VRAM

With one GPU, three apps each loading their own models would triple VRAM for no benefit. That —
not code organization — is the real constraint driving topology.

**Caveat:** inside a FLAME call you must specify `{:local, ServingName}` to force non-distributed
execution.

---

## Data flow: ingest

Uniform across all three apps. This is the `core` pattern extracted from `document-sorter`.

```
file_watcher (FileSystem)
      │  new/changed path
      ▼
Oban :scan          →  create/update entity row
      │
      ▼
Oban :extract       →  POST sidecar (music) | ffprobe (video) | extractor module (docs)
      │                 returns NAMED features / metadata
      ▼
Oban :embed         →  Nx.Serving.batched_run on the inference node
      │
      ▼
Oban :classify      →  instruments / scene tags / document category
      │
      ▼
Oban :derive        →  vector assembly, normalization, pgvector write   [Elixir owns this]
```

Every step is idempotent and queries for rows *lacking* the relevant data, so re-running is cheap.
This preserves the resumability property the current Python `rebuild` pipeline has.

### Queue sizing

Concurrency lives in **one place: Oban's per-queue `limit`.** Do not let a worker process run its
own thread pool underneath — two schedulers competing for the same cores will either idle the box
or exhaust it, non-obviously.

| Queue | Bound by | Suggested limit |
|---|---|---|
| `:scan` | I/O | 4–8 |
| `:extract` | CPU (librosa / ffprobe) | ≈ core count |
| `:embed` | VRAM | 1–2 |
| `:classify` | VRAM | 1–2 |
| `:derive` | CPU, cheap | 4–8 |
| `:transcode` | CPU, heavy | 1–2 |

Set a generous per-job `timeout`. Full analysis of a long track takes minutes and Oban's default
will kill it mid-flight.

Oban Web became open source and free in Oban 2.19 — use it. Global (cluster-wide) concurrency
limits and rate limiting remain Oban Pro features; local per-node limits are open source and
sufficient for a single-node deployment.

---

## Schema ownership

**Ecto owns the schema. Full stop.** The Python sidecar has no database credentials and never
writes. Dual schema ownership across two languages is where this kind of split rots.

Consequences:

- The sidecar is stateless — restart or redeploy freely; in-flight jobs simply retry.
- Migrations live in one place, in one language.
- The sidecar contract is versioned independently of the schema (see
  [05-python-sidecar-contract.md](05-python-sidecar-contract.md)).

---

## pgvector strategy

Several vector columns with very different dimensionality and cardinality now share one database:

| Vector | Dim | Volume |
|---|---|---|
| Song engineered features | 107 | one per song |
| Song CLAP embedding | 512 | one per song |
| Segment engineered features | 107 | **many per song** — the largest table |
| Segment CLAP embedding | 512 | many per song |
| Document chunk embedding | model-dependent | many per document |
| Video scene embedding | model-dependent | many per video |

**Index choice.** HNSW is the right default — better recall, no training step — but it is
memory-hungry, and the segment tables are the big ones. Plan where those indexes live and expect
to tune `m` / `ef_construction` per table rather than globally.

**Hybrid search.** Both the RAG app and music search want keyword *and* vector results fused.
pgvector-elixir ships a hybrid-search example using Reciprocal Rank Fusion, which avoids tuning a
blend weight. This belongs in `core`.

**Raw vectors stay queryable.** Keep the unnormalized vector alongside the normalized pgvector
column (the current design stores it in `features_json["vector"]`). Re-normalization then never
requires re-reading media — critical given how often weights will change.
