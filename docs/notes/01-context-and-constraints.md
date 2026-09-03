> **Non-normative.** Where this conflicts with
> [spec-01](../spec-01-catalog-data-model.md), the specification governs.
>
> **Superseded here:** the single-user constraint and the multi-user non-goal — the system serves a household of several principals (spec-01 §10–11); and the two-codebase migration framing, since the project is greenfield.

# 01 — Context and Constraints

## What this replaces

Plex, for music and video. The specific grievances driving the move:

1. **No plugin system.** Nothing can be extended or substituted.
2. **Weak playlist creation and management.**
3. **A poor Android Auto app.** Notably *not* a platform limitation — see
   [02-protocol-landscape.md](02-protocol-landscape.md#layer-3--control-surfaces).

What Plex does well and must be replaced, not just abandoned:

- **Device breadth.** Roughly fifteen hand-written native clients. This is the real moat and it
  cannot be out-built directly. The strategy is to speak protocols whose clients already exist.
- **Plexamp.** Genuinely best-in-class for music. Sonic Adventure (path between two tracks),
  Mood Radio (8 named moods: brooding, cathartic, confident, intense, playful, poignant,
  swaggering, wistful), DJ modes (Stretch / Contempo / Groupie), and ~50 weighted parameters from
  its "Super Sonic" analysis. This is the bar for the music experience.

## Constraints

These are load-bearing. Most later decisions follow from them.

| Constraint | Consequence |
|---|---|
| **Single user** | Collaborative filtering is impossible. Everything must be content-based. Spotify's Daily Mix mechanism is permanently unavailable; its *qualities* are not. |
| **Local media only** | Streaming-service provider integrations are irrelevant. Music Assistant's value to us is entirely its player/output layer, not its music-provider layer. |
| **One GPU** | Inference must be shared across all three apps, not duplicated per app. Drives the `Nx.Serving` federation decision in [03-system-architecture.md](03-system-architecture.md). |
| **One Postgres** | pgvector becomes load-bearing across music, documents, and video. Index strategy is a shared concern. |
| **Personal project, no deadline** | Favours long-term maintainability over time-to-first-result. Justifies a runtime migration. |
| **Indefinite maintenance horizon** | Favours low-churn ecosystems. Elixir over Node for this reason specifically. |
| **Docker-based deployment** | Language boundaries are cheap. A polyglot sidecar is an acceptable cost, not a failure. |

## Existing inputs

### `music-analysis` (Python)

Originally an *analysis* tool; playback was added later to cross-check results. That history
matters: the serving layer was never a deliberate design, which is why it is the part being
replaced.

- FastAPI + Typer CLI, librosa, CLAP, chromaprint, Postgres + pgvector
- Vue 3 SPA (Pinia, Tailwind v4) served separately via Vite in dev
- 107-dimension engineered feature vector with a fixed canonical order
- Per-song **and per-segment** features, embeddings, and likes
- Entities: `Artist`, `Album`, `Song`, `SongFeatures`, `SongEmbedding` (512-dim CLAP),
  `SongSegment`, `SegmentFeatures`, `SegmentEmbedding`, `SongLyrics`, `SongFingerprint`,
  `SongInstruments`, `SongDuplicate`, `CorruptFile`, `User`, `UserSegmentLike`, `UserTasteProfile`

Known gaps in the current schema:

- **No `Playlist` entity.** Playlists are generated and exported, never persisted.
- **No play/listen history.** Only likes exist, so "familiarity" is not computable.
- **`UserTasteProfile.user_id` is `unique: true`** — exactly one taste centroid per user, which
  models taste as unimodal. See [07-analysis-taste-and-playlists.md](07-analysis-taste-and-playlists.md).

### `document-sorter` (Elixir/Phoenix)

Already on the target stack, and already contains the ingestion skeleton the other two apps need.

- Phoenix 1.8.5, LiveView 1.1, Bandit, Ecto 3.13
- Oban 2.18, pgvector 0.3, `file_system`
- Bumblebee 0.6, Nx 0.9, EXLA, Axon 0.7
- Extractors: `bupe` (epub), `docxelixir`, `xlsxir`, `exoffice`, `earmark`, `ex_pdf_poppler`
- `ml/{embedding_serving,classifier_serving,llm_client}.ex`
- `ingestion/{file_watcher,extraction_worker,embedding_worker,classification_worker,summarization_worker}.ex`

**The ingestion pipeline generalizes directly.** This is the single most valuable existing asset:

| document-sorter | music | video |
|---|---|---|
| `file_watcher` | library scan | library scan |
| `extraction_worker` | feature extraction | probe + scene detection |
| `embedding_worker` | CLAP encoding | frame/scene embeddings |
| `classification_worker` | instrument detection | content tagging |
| `summarization_worker` | lyric analysis | subtitle summarization |
| `ml/embedding_serving` | CLAP serving | CLIP serving |
| `extractor/{pdf,docx,…}` | per-codec decode | per-container demux |

Extract this into a shared `core` library **before** writing the second app.

Known gap: no OCR path, so scanned PDFs extract empty (the existing `reextract_empty` mix task
suggests this has already been hit). See `kreuzberg` in
[04-elixir-package-reference.md](04-elixir-package-reference.md).

## Prior art we are measured against

**AudioMuse-AI** — the closest existing project. Python, Librosa, Postgres, containerized
worker/web split, ONNX models (MusiCNN 200-dim, DCLAP 512-dim, Whisper, Silero, GTE 768-dim).
Integrates with Navidrome, Jellyfin, Emby, Lyrion, and Plex; ships as the `sonicSimilarity`
provider for Navidrome and Ampache. Uses its `task_status` table as a queue with Postgres
`LISTEN`/`NOTIFY` rather than a broker.

Read its `ARCHITECTURE.md` and `ALGORITHM.md` before designing. **Where we differ:** it clusters
whole tracks; we model segments. That difference is the entire justification for building.

**Navidrome** — WASM plugin system built on Extism. Capabilities detected from module exports
(`MetadataAgent`, `Scrobbler`, `Lyrics`, `SonicSimilarity`), distributed as `.ndp` packages,
host services for scheduling, caching, artwork, and Subsonic callbacks. The reference model if we
ever want our own extension system.

**Symfonium** — one Android UI over Plex, Emby, Jellyfin, Subsonic/OpenSubsonic, Kodi,
Audiobookshelf, SMB, WebDAV, and cloud storage, with good Android Auto support. Worth testing
against the existing Plex server immediately; it may resolve the car complaint on its own.

## Non-goals

- Writing native clients for any platform.
- Implementing AirPlay, Cast, or Sonos protocols from scratch (consume existing implementations).
- Multi-user support, sharing, or federation.
- Matching Plex's video metadata scraping breadth.
- Collaborative filtering or anything requiring a user population.
