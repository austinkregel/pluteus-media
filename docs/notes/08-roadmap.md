> **Non-normative.** Where this conflicts with
> [spec-01](../spec-01-catalog-data-model.md), the specification governs.
>
> **Superseded here:** the entire phase plan. The project is greenfield against spec-01, not a migration, so Phases 0–6 do not apply and the existing database is not an import source.

# 08 — Roadmap

Ordered so that each phase is independently useful and the decision to continue stays reversible
for as long as possible. This matters more than usual: it is a personal project being migrated for
enjoyment, and a stall should leave something better than it found.

---

## Phase 0 — Do this regardless

Cheap, and impossible to reconstruct later.

- [ ] **Add `extractor_version` to `song_features` and `segment_features`; backfill.** One line of
      Python. Without it, "which rows came from which extractor build" is unanswerable forever.
- [ ] **Test Symfonium against the existing Plex server.** It may resolve the Android Auto complaint
      this week, independent of everything else here. Costs an evening.
- [ ] **Read AudioMuse-AI's `ARCHITECTURE.md` and `ALGORITHM.md`.** Closest prior art; several
      decisions here are downstream of it.
- [ ] Store MBIDs — resolve existing chromaprint fingerprints through AcoustID. Makes the library
      interoperable with ListenBrainz, Troi, JSPF, and every metadata tool, and makes any future
      spec proposal far easier to argue.

---

## Phase 1 — Extract the shared core

From `document-sorter`, into a `core` library consumed by all three apps.

- [ ] Oban ingestion pipeline pattern (watch → extract → embed → classify → derive)
- [ ] pgvector helpers, distance wrappers, HNSW/IVFFlat index migrations
- [ ] Hybrid search (Reciprocal Rank Fusion) — both RAG and music search need it
- [ ] `Nx.Serving` client wrappers
- [ ] `FileSystem` watcher with debounce and stability checks

Do this **before** writing the second app, not after.

---

## Phase 2 — Sidecar-ize the analyzer

No Elixir yet. Purely a refactor of the existing Python app.

- [ ] Wrap `analyze_one_song` in a thin FastAPI app: `POST /analyze {path}` → named features
- [ ] Delete the `ThreadPoolExecutor`; one song per request, synchronous
- [ ] Emit `schema_version` and `extractor_version`
- [ ] Keep the existing CLI path working alongside it
- [ ] **Parity harness:** assert in-process and sidecar produce byte-identical numbers
- [ ] Golden fixtures — a few audio files with committed expected output

**Exit criterion:** the sidecar reproduces current results exactly.

---

## Phase 3 — Phoenix, read-only

The highest-value, lowest-risk phase. No writes, so nothing can be corrupted.

- [ ] Phoenix app against the **existing schema**, read-only Ecto schemas
- [ ] **OpenSubsonic adapter** — browsing, search, `stream`, `getCoverArt`
- [ ] API key authentication (`apiKeyAuth` extension); legacy salt/token only for compatibility
- [ ] `getOpenSubsonicExtensions` advertising what is actually implemented
- [ ] Validate against real clients: Symfonium, Feishin, Music Assistant

**Exit criterion:** music plays on a phone and in the car, from the existing database, with no
writes and the Python app still running.

This is also where the Elixir decision is validated cheaply. If it turns out to be wrong, a weekend
was spent, not the project.

---

## Phase 4 — Playlists and similarity

- [ ] **`Playlist` entity** with CRUD — blocks both OpenSubsonic and generated mixes, and is one of
      the three original grievances
- [ ] `createPlaylist` / `updatePlaylist` / `deletePlaylist` / `getPlaylists` / `getPlaylist`
- [ ] **`getSimilarSongs` / `getSimilarSongs2`** backed by our vectors — immediately better than
      every other server, which needs a Last.fm key for this
- [ ] Song-level projection of segment likes for `star` / `unstar` / `setRating`
- [ ] `sonicSimilarity`: `getSonicSimilarTracks`, then `findSonicPath`

**Exit criterion:** Music Assistant's "Don't Stop the Music" runs on our acoustic analysis.

---

## Phase 5 — Take over writes

- [ ] Move vector assembly and normalization into Elixir (single ordering module)
- [ ] Validate: recompute all vectors in both implementations and diff per dimension against the
      raw values in `features_json["vector"]`, before normalization can mask anything
- [ ] Flip ingestion to Oban, calling the sidecar
- [ ] `playbackReport` extension + `scrobble` + a **listen-events table** — unlocks familiarity
- [ ] Ecto becomes the sole schema owner; Alembic retires

**Exit criterion:** Python only runs when Oban asks it to.

---

## Phase 6 — Delete

- [ ] `web.py`, the whole `frontend/`, the pipeline half of `cli.py`
- [ ] `db.py`, `similarity.py`, `taste.py`, `recommendation.py`, `vector_norm.py`
- [ ] The Vue SPA, Pinia stores, Vite config, and the Node build stage in the Dockerfile

The image drops the entire Node stage; the sidecar image drops FastAPI's web surface.

---

## Phase 7 — The differentiated work

Only now, because everything above is prerequisite.

- [ ] **k-component taste clustering** (`Scholar.Cluster.KMeans` / `GaussianMixture`) — write it
      this way rather than porting the single-centroid version first
- [ ] Per-theme dimension weight overrides
- [ ] Set-level coherence constraint in candidate selection
- [ ] **Duration-targeted playlists** — cheapest genuinely novel feature
- [ ] Playlist sequencing (HAM-2, then TSP cycle)
- [ ] Playlist naming via the existing `llm_client`
- [ ] Arc shaping using dynamic-arc coefficients

---

## Phase 8 — Expand

- [ ] LiveView UI replacing the Vue pages, one at a time
- [ ] Video app: scan, probe, artwork, trickplay, subtitles, direct play + transcode
- [ ] Inference node split out; `libcluster` topology
- [ ] Optional native output (`airplay`, `snapcast`)
- [ ] Segment-aware transitions
- [ ] Scene analysis for video (Membrane per-frame pipeline)

---

## Reversibility

| Through phase | Rollback cost |
|---|---|
| 0–2 | None. Pure additions to the Python app. |
| 3 | Delete a directory. The Python app never stopped working. |
| 4 | Same — still no writes to shared state beyond new playlist tables. |
| 5 | Real. Elixir now owns writes and schema. This is the commitment point. |
| 6+ | Committed. |

**Phase 5 is the door.** Everything before it is reversible; nothing after it is. Spend as long as
useful in phases 3–4.

---

## Non-obvious sequencing notes

- **`extractor_version` before anything else.** It is the only item here that becomes impossible if
  deferred.
- **Read-only Phoenix before any write path.** It validates the runtime choice, the schema mapping,
  and real client compatibility simultaneously, at zero risk.
- **`getSimilarSongs` before `sonicSimilarity`.** The former is what Music Assistant actually calls
  and what every Subsonic client's radio button hits. The latter is more interesting but less used.
- **Play history before themed playlists.** Familiarity is half the mechanism and is not computable
  without it.
- **Duration targeting before transitions.** Less work, more differentiated, more relevant to the
  actual driving use case.
- **Write the k-component taste model directly.** Porting the unimodal version first means writing
  it twice.
